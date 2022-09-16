using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Test;
using Toybox.AntPlus;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Notes.    
// Functional, w/ Old code:      Code 5109 bytes, Data 1790 bytes.
// Functional  removed old code: Code 4110 bytes, Data 1451 bytes.

class BatteryBurnRateView extends WatchUi.DataField {

	// Algorithm, v2.
	// Capture 16 data points per hour, plus a data point on battery 
	// level change.   So the estimate is based upon at most one hour of 
	// data, or less if the battery is dropping faster. 
	
	// Primary data point collection.
	const      pdp_data_points    = 16;              // This make masks easy.   ATTN! Must be 2^N
	const      pdp_data_mask = pdp_data_points - 1;  

	// The timeout determines the baseline sampling rate.  Keep at most a hour of data.
	const      pdp_sample_timeout_tunable = 225*1000; // Capture a data point if no change...
	var        pdp_sample_timeout_ms;                 // The countdown variable.
	var        pdp_sample_time_last_ms; 

	hidden var pdp_data_battery;        // Battery data points.
	hidden var pdp_data_time_ut;	    // Timestamps to go with the data. 
	hidden var pdp_data_i;	            // Index.  Use with a mask.

	hidden var start_t0_ut;             // For logging

	hidden var pdp_battery_last;        // Trigger data collection on  battery level change.

	hidden var charging;                // Save the state. 

	hidden var burn_rate_slope;            // Burn rate as a slope. 

	// TUNABLES 
	// Make the display red if burn rate exceeds 12%/h 
	const veryHighBurnRate = -12.0;
	
	// Reset the data collection system.
   function data_reset() {
		pdp_data_i = 0; // The total number of samples.
		pdp_sample_time_last_ms = System.getTimer(); 
		pdp_sample_timeout_ms   = pdp_sample_timeout_tunable / 2;  

		burn_rate_slope = 0.0;
 	  }
 

    // Set the label of the data field here.
    function initialize() {
        DataField.initialize();

		pdp_data_time_ut = new [ pdp_data_points ];
		pdp_data_battery = new [ pdp_data_points ];
		pdp_battery_last = 200.0; // Set this to an invalid value so that it triggers immediately.

		start_t0_ut      =  Time.now().value();

		charging = null;

		data_reset();

		var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
		var dateString = Lang.format(
	    	"$1$-$2$-$3$ $4$:$5$:$6$",
		    [
   		 	today.year, today.month, today.day,
    	    today.hour, today.min, today.sec
    		] );

		System.println("# BatteryBurnRate Started " + dateString);
		System.println("# time(h), time(s), battery level, charging(Y/N)");
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
		} else if (dc.getHeight() > 100) {
            View.setLayout(Rez.Layouts.LargestLayout(dc));
            var labelView = View.findDrawableById("label");
            labelView.locY = labelView.locY - 15;
            // var valueView = View.findDrawableById("value");
            // valueView.locY = valueView.locY + 12;
		} else if (dc.getHeight() > 65) {
            View.setLayout(Rez.Layouts.LargerLayout(dc));
            var labelView = View.findDrawableById("label");
            labelView.locY = labelView.locY - 12;
            // var valueView = View.findDrawableById("value");
            // valueView.locY = valueView.locY + 11;
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
    function update_estimate() {

		// If there isn't enough data, stop now. 
		if ( pdp_data_i < 2 ) {
			// TODO: Put some code here to generate a message. 
			// System.println("# Too Soon to estimate()");
			burn_rate_slope = 0.0;
			return;
			}

		// Fit to whatever is present, even if its not much.
		var data_offset  = pdp_data_i; // This should be the oldest point.

		// Partial data is a special case. Start at zero. 
		if ( data_offset < pdp_data_points ) { data_offset = 0; }

		var fitsize = pdp_data_i;
		if ( fitsize > pdp_data_points ) { fitsize = pdp_data_points; }

		// Make a snapstop of the real data and align it + normalize to hours.
		// Recall that the data buffer pointer is always pointing to the oldest item in the ring. 
		var data_x       = new [ pdp_data_points ];
		var data_y       = new [ pdp_data_points ];

		{
			var t0 = pdp_data_time_ut[data_offset & pdp_data_mask];

			// Convert from seconds to hours...

			for (var i=0; i < fitsize; i++) {
				var adj_i = (i + data_offset) & pdp_data_mask; 

				var ut = pdp_data_time_ut[adj_i];

				// Seconds to Hours. 
      			data_x[i] = (ut - t0) *  0.000277777777777777777777; 
				data_y[i] = pdp_data_battery[adj_i];
    		}
		}

		// From https://www.mathsisfun.com/data/least-squares-regression.html

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
			var denom = fitsize * sum_xx - sum_x * sum_x; 

			// Check for divide by zero and zero slope
			if ( num == 0.0 || denom == 0.0 ) {
				burn_rate_slope = 0.0;
			} else {
				burn_rate_slope = num / denom; 
			}
			// System.println("# extrapolate," + burn_rate_slope.format("%.1f") );
		}
		// The input unit is already in percent. 

	}

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().

	// Notes on data collection -
	// The primary collection loop uses the system ms timer along with 
	// a running error a la Bresenhams algorithm.

	// Collect a data point when the Battery level changes or there has been a timeout.  
	// The net result of this is that the app keeps at most an hour of data,
	// and less if the battery level is changing fast. 

    function compute(info) {

		var systemStats = System.getSystemStats();

		// Handle the case where the stats are null.
		var n_charging = systemStats == null ? null : systemStats.charging;

		// Pre-business.   Check for a change in system battery state, 
		// and if it happens, reset data collection and re-start measurement.
		// do this rather than exiting early so that the rest of the system is 
		// in a good state.   
		if ( ( n_charging == null ) || ( n_charging != charging )  ) {
			charging = n_charging;
			data_reset();
			return; 
		}

		// Update the timeout. 
		var timeout_happened; 
		{
			var now = System.getTimer();
			var duration = now - pdp_sample_time_last_ms;
			pdp_sample_time_last_ms = now;

			pdp_sample_timeout_ms -= duration; // Use Bresenhams Algorithm.

			if ( pdp_sample_timeout_ms  <= 0 ) {
				timeout_happened = 1;
				pdp_sample_timeout_ms += pdp_sample_timeout_tunable;
				// System.println("Sampling Timeout"); 
 			}
			else { timeout_happened = 0; }
		} 

		// Now decide whether or not to keep the sample.
		// if things are plugged in, no. FIXME 

		// RS: Maybe this isn't necessary if the app simply declines 
		// to show bogus data. 
		var battery = systemStats.battery;

		// If the value of the battery percentage has changed 
		// or a timeout has occurred, capture a data point. 
		// var delta = (pdp_battery_last - battery).abs();
		// if ( (delta < 1.0) && (timeout_happened == 0) ) { return; } 

		// if ( pdp_battery_last == battery ) { return; } 
		if ( timeout_happened == 0 && pdp_battery_last == battery ) { return; } 

		var i      = pdp_data_i & pdp_data_mask;

		pdp_data_time_ut[i] =  Time.now().value();

		// Logging
		if ( pdp_battery_last != battery ) {
			var ts = pdp_data_time_ut[i] - start_t0_ut;
			var formatted = "";
			formatted += ts* 0.000277777777777777777777 + ",";
			formatted += ts + ",";
			formatted += battery + ",";
			if ( charging == 0 ) {
				formatted += "N";
			} else {
				formatted += "Y";
			}

			System.println(formatted); 
		}

		// Do these with larger operations to lower logging overhead.
		//if ( timeout_happened ) {
		//	System.println(pdp_data_i + "," + pdp_data_time_ut[i] + "," + battery + ",to"); 
		//} else {
		//	System.println(pdp_data_i + "," + pdp_data_time_ut[i] + "," + battery ); 
		//}

		pdp_data_battery[i] = battery;
		pdp_battery_last    = battery;

		pdp_data_i++;

		update_estimate();
    }
    
	function showRemain(burnRate)
	{
		var systemStats = System.getSystemStats();
		var calculated_remain = View.findDrawableById("remain");
		var burnRateAsNum = burnRate;
		if (burnRate != null && burnRate instanceof String) {
			if (burnRate == "Calculating...") {
				burnRateAsNum = null;
			}
			//System.println("burn rate before conversion to float is " + burnRate);
			burnRateAsNum = burnRate.toFloat();
		}
		if (systemStats != null && systemStats.battery != null && burnRateAsNum != null && burnRateAsNum > 0) {
			var calcRemain = systemStats.battery / burnRateAsNum;
			//System.println("Time remaining is " + calcRemain + " with battery of " + systemStats.battery + " and burn of " + burnRateAsNum + " rate " + burnRate);
			if (calculated_remain != null) {
				if (calcRemain > 1) {
					calculated_remain.setText(calcRemain.format("%.1f") + " hours left");
				} else {
					calculated_remain.setText((calcRemain*60).format("%.1f") + " minutes left");
				}
			}
		}
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

		// Display Burn and Charge separately.  Charging isn't necessarily valid.
		if ( charging == true )  {
	        label.setText("Charge/h");
		} else { 
		    label.setText("Burn/h");
		}
		// Display the data.  If its an invalid value, render as dashes
        var value = View.findDrawableById("value");
		//System.println("Width is " + dc.getWidth() + " height is " + dc.getHeight());
		//System.println("Value is " + value.width + " x " + value.height);
		/* if (dc.getHeight() > 100) {
			value.setSize( value.width * 1.1, value.height * 1.1);
		}
		else if (dc.getHeight() > 75) {
			value.setSize( value.width * 1.05, value.height * 1.05);
		} */
        if (  burn_rate_slope != 0 ) {

			// Check for pathology and set the color if need be. 
			if ( burn_rate_slope < veryHighBurnRate ) {
			    dataColor = Graphics.COLOR_RED;
			}

			var abs_d = burn_rate_slope.abs();
	        value.setText(abs_d.format("%.1f") + "%");
			if (dc.getHeight() > 80) {
				showRemain(abs_d);
			}
        } else {
        	value.setText("-wait-");
    	}

		// Done with Formatting, choose the color.
        value.setColor(dataColor);
		
        View.onUpdate(dc);
	}    	
}