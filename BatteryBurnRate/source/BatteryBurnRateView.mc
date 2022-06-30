using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Test;
using Toybox.AntPlus;
using Toybox.Time;

// Notes.    
// Functional, w/ Old code:  Code 5109 bytes, Data 1790 bytes.


class BatteryBurnRateView extends WatchUi.DataField {

	// --------------------------------------------------------------
	// Debug Control - Also triggers Printlns.
	const do_simulate = 0; // The time code is broken in sim.   Fake it.


	// Algorithm, v2.   Capture primary data points every 
	// time the battery charge changes more than 1%  
	var   sim_ut;
	
	// Primary data point collection.
	const      pdp_data_points    = 16;          // This make masks easy.

	const      pdp_sample_timeout_tunable = 300*1000; // Capture a data point if no change...
	var        pdp_sample_timeout_ms;                 // The countdown variable.
	var        pdp_sample_time_last_ms; 

	hidden var pdp_data_battery;        // Battery data points.
	hidden var pdp_data_time_ut;	    // Timestamps to go with the data. 
	hidden var pdp_data_i;	            // Index.  Use with a mask.

	hidden var pdp_battery_last;        // Trigger data collection on  battery level change.

	hidden var burn_rate_slope;            // Burn rate as a slope. 
	const      burn_rate_invalid = 1000.0; // A Magic Value  

	// TUNABLES 
	// Make the display red if burn rate exceeds 12%/h 
	const veryHighBurnRate = -12.0;
	
    // Set the label of the data field here.
    function initialize() {
        DataField.initialize();

		pdp_data_i = 0; // The total number of samples.
		pdp_sample_time_last_ms = System.getTimer(); 
		pdp_sample_timeout_ms   = 0; 

		pdp_data_time_ut = new [ pdp_data_points ];
		pdp_data_battery = new [ pdp_data_points ];
		pdp_battery_last = 200.0; // Set this to an invalid value so that it triggers immediately.

		burn_rate_slope = 0.0;

		sim_ut = 0; 
    }

    // Set your layout here. Anytime the size of obscurity of
    // the draw context is changed this will be called.
    function onLayout(dc) {
        var obscurityFlags = DataField.getObscurityFlags();

        // Top left quadrant so we'll use the top left layout
        if (obscurityFlags == (OBSCURE_TOP | OBSCURE_LEFT)) {
            View.setLayout(Rez.Layouts.TopLeftLayout(dc));

        // Top right quadrant so we'll use the top right layout
        } else if (obscurityFlags == (OBSCURE_TOP | OBSCURE_RIGHT)) {
            View.setLayout(Rez.Layouts.TopRightLayout(dc));

        // Bottom left quadrant so we'll use the bottom left layout
        } else if (obscurityFlags == (OBSCURE_BOTTOM | OBSCURE_LEFT)) {
            View.setLayout(Rez.Layouts.BottomLeftLayout(dc));

        // Bottom right quadrant so we'll use the bottom right layout
        } else if (obscurityFlags == (OBSCURE_BOTTOM | OBSCURE_RIGHT)) {
            View.setLayout(Rez.Layouts.BottomRightLayout(dc));

        // Use the generic, centered layout
        } else {
            View.setLayout(Rez.Layouts.MainLayout(dc));
            var labelView = View.findDrawableById("label");
            labelView.locY = labelView.locY - 16;
            var valueView = View.findDrawableById("value");
            valueView.locY = valueView.locY + 7;
        }

        View.findDrawableById("label").setText(Rez.Strings.label);
        return true;
    }

	// Calculate the least squares fit of the data. 
    function estimate() {

		// If there isn't enough data, stop now. 
		if ( pdp_data_i < 2 ) {
			// TODO: Put some code here to generate a message. 
			burn_rate_slope = burn_rate_invalid;
			return;
			}

		// Fit to whatever is present, even if its not much.
		var data_offset  = pdp_data_i; // This should be the oldest point.

		// Partial data is a special case. Start at zero. 
		if ( data_offset < pdp_data_points ) { data_offset = 0; }

		var fitsize = pdp_data_i;
		if ( fitsize > pdp_data_points ) { fitsize = pdp_data_points; }

		if ( do_simulate ) { System.print("Estimate: "); }
		// Make a snapstop of the real data and align it + normalize to hours.
		// Recall that the data buffer pointer is always pointing to the oldest item in the ring. 
		var data_x       = new [ pdp_data_points ];
		var data_y       = new [ pdp_data_points ];

		{
			var t0 = pdp_data_time_ut[data_offset & 0xf];

			// Convert from seconds to hours...

			for (var i=0; i < fitsize; i++) {
				var adj_i = (i + data_offset) & 0xf; 

				var ut = pdp_data_time_ut[adj_i];

				// Seconds to Hours. 
      			data_x[i] = (ut - t0) *  0.000277777777777777777777; 
				data_y[i] = pdp_data_battery[adj_i];
    		}
		}

		// From https://www.mathsisfun.com/data/least-squares-regression.html

		var slope; 
		{
			var sum_x, sum_y, sum_xx, sum_xy; 
			sum_x = 0.0; sum_y = 0.0; sum_xx = 0.0; sum_xy = 0.0;
			for (var i=0; i < fitsize; i++){
				sum_x  += data_x[i]; 
				sum_y  += data_y[i];
				sum_xx += data_x[i] * data_x[i]; 
				sum_xy += data_x[i] * data_y[i]; 
    		}

			var num   = fitsize * sum_xy - sum_x * sum_y; 
			var denom = fitsize * sum_xx - sum_xx; 

			// Check for divide by zero.
			if ( denom != 0.0 ) { slope = num / denom; }
			else                { slope = 0.0; }
		}

		// The input unit is already in percent. 
		if ( do_simulate ) {  System.println("Pct/H: " + slope.format("%.1f") ); }
		burn_rate_slope = slope; 
	}

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().

	// Notes on data collection -
	// The primary collection loop uses the system ms timer along with 
	// a running error a la Bresenhams algorithm.

	// Collect a data point when the Battery level changes by at least 1% 
	// or there has been a timeout.  

    function compute(info) {

		// The simulator is broken.   Generate time.
		if ( do_simulate == 1 ) { sim_ut++; } 

		// Update the timeout. 
		var timeout_happened; 
		{
			var now = System.getTimer();
			var duration = now - pdp_sample_time_last_ms;
			pdp_sample_time_last_ms = now;

			pdp_sample_timeout_ms -= duration; // Use Bresenhams Algorithm.

			if ( pdp_sample_timeout_ms  < 0 ) {
				timeout_happened = 1;
				pdp_sample_timeout_ms += pdp_sample_timeout_tunable;
				System.println("Sampling Timeout"); 
 			}
			else { timeout_happened = 0; }
		} 

		// Now decide whether or not to keep the sample.
		// if things are plugged in, no. FIXME 
		// RS: Maybe this isn't necessary if the app simply declines 
		// to show bogus data. 
		var systemStats = System.getSystemStats();
		var battery = systemStats == null ? null : systemStats.battery;
		if ( battery == null ) { return; }

		// If the value of the battery percentage has changed more than 
		// 1%, or a timeout has occurred, capture a data point. 
		var delta = (pdp_battery_last - battery).abs();
		if ( (delta < 1.0) && (timeout_happened == 0) ) { return; } 

		pdp_battery_last = battery;

		if ( do_simulate ) { 
			System.println("Sample PDP Add " + pdp_data_i + " " + battery ); 
		}

		var now_ut = new Time.Moment(Time.today().value()); 
		var i      = pdp_data_i & 0xF;

		if ( do_simulate == 1 ) {
			pdp_data_time_ut[i] = sim_ut; 
		} else {
			pdp_data_time_ut[i] = now_ut.value();
			}	

		pdp_data_battery[i] = battery;
		pdp_data_i++;

		estimate();
    }
    
   //! Display the value you computed here. This will be called
    //! once a second when the data field is visible.
    function onUpdate(dc) {
	    var dataColor;
        var label = View.findDrawableById("label");

		// Reverse the colors for day/night and set the default 
		// value for the color of the data color. 
	    if (getBackgroundColor() == Graphics.COLOR_BLACK) {
	        label.setColor(Graphics.COLOR_WHITE);
			dataColor = Graphics.COLOR_WHITE;
	    } else {
	        label.setColor(Graphics.COLOR_BLACK);
			dataColor = Graphics.COLOR_BLACK;
		}
        View.findDrawableById("Background").setColor(getBackgroundColor());

		// Display Burn and Charge separately.
		if ( burn_rate_slope > 0.0 )  {
	        label.setText("Charge/h");
		} else { 
		    label.setText("Burn/h");
		}

		// Check for pathology and set the color if need be. 
		if ( burn_rate_slope < veryHighBurnRate ) {
		    dataColor = Graphics.COLOR_RED;
		}

		// Display the data.  If its an invalid value, render as dots. 
        var value = View.findDrawableById("value");
        if (  burn_rate_slope != burn_rate_invalid ) {
	        value.setText(burn_rate_slope.format("%.1f") + "%");
        } else {
        	value.setText("...");
    	}

		// Done with Formatting, choose the color.
        value.setColor(dataColor);
		
        View.onUpdate(dc);
	}    	
}