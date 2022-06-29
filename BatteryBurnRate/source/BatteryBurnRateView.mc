using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Test;
using Toybox.AntPlus;
using Toybox.Time;

class BatteryBurnRateView extends WatchUi.DataField {

	// Algorithm, v2.   Capture primary data points every 
	// approximately every 4 minutes.  
	const do_simulate = 0; // The time code is broken in sim.   Fake it.
	var   sim_ut;
	
	// Primary data point collection.
	const pdp_sample_interval_ms = 4*60*1000; // Set low for debug.
	const pdp_data_points        = 16;    // This make masks easy.

	// Running sample time.
	hidden var pdp_sample_interpolater; // Used to decide when to keep a sample
	hidden var pdp_sample_time_last_ms;     

	hidden var pdp_data_battery;        // Battery data points.
	hidden var pdp_data_time_ut;	    // Timestamps to go with the data. 
	hidden var pdp_data_i;	            // Index.  Use with a mask.

	const secondsInHour = 36;
	const warmupTime = 12;
	const veryHighBurnRate = 12;
	const lowMemoryDivisor = 6;
	var batteryValues;
	var timesForBattery;
	var lowMemoryMode = false;	
	
	var startingTimeInMs;
	var lastBurnRate;
	var currentBurnRate;
	
    // Set the label of the data field here.
    function initialize() {
        DataField.initialize();

		// Interpolator initialization.
		pdp_sample_interpolater = 0; // Start with zero to capture a point now.. 
		pdp_sample_time_last_ms = 0;  
		pdp_data_i = 0; // The total number of samples.
		pdp_data_time_ut = new [ pdp_data_points ];
		pdp_data_battery = new [ pdp_data_points ];

        startingTimeInMs = System.getTimer();
        lastBurnRate = 0;
        currentBurnRate = 0;
		if (System.getSystemStats().freeMemory > 20000) {
			batteryValues = new [secondsInHour];
			timesForBattery = new [secondsInHour];
		} else {
			batteryValues = new [secondsInHour/6];
			timesForBattery = new [secondsInHour/6];
			lowMemoryMode = true;		
		}

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
    function extrapolate() {

		// First - if there isn't enough data, stop now. 

		if ( pdp_data_i < 2 ) {
			// TODO: Put some code here to generate a message. 
			return;
			}

		// Fit to whatever is present, even if its not much.
		var data_offset  = pdp_data_i; // This should be the oldest point.

		// Partial data is a special case. Start at zero. 
		if ( data_offset < pdp_data_points ) { data_offset = 0; }

		var fitsize = pdp_data_i;
		if ( fitsize > pdp_data_points ) { fitsize = pdp_data_points; }

		System.print("Extrapolate: ");
		// Make a snapstop of the real data and align it + normalize to hours.
		// Recall that the data buffer pointer is always pointing to the oldest 
		// item in the ring. 
		var data_x       = new [ pdp_data_points ];
		var data_y       = new [ pdp_data_points ];

		{
			var t0 = pdp_data_time_ut[data_offset & 0xf];

			// Convert from seconds to hours...

			for (var i=0; i < fitsize; i++) {
				var adj_i = (i + data_offset) & 0xf; 

				var ut = pdp_data_time_ut[adj_i];

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
			else                { slope = 0; }
		}

		// The input unit is already in percent. 
		System.println("Pct/H: " + slope.format("%.1f") );

		// Calculate the expected runtime from the most recent data point. 
		// Look out for divide by zero errors
		var batt_level = pdp_data_battery[ (pdp_data_i-1) & 0xf];
		var runtime_estimate; 
		if ( slope < 0 ) { 
			runtime_estimate = -1.0 * batt_level / slope; 
		} else { runtime_estimate = 48.0; }

		if ( runtime_estimate > 48.0 ) {
			System.println("Estimate(h) 48h+" + runtime_estimate );
		} else {
			System.println("Estimate(h) " + runtime_estimate );
		}
	}

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().

	// Notes on data collection -
	// The primary collection loop uses the system ms timer along with 
	// a running error a la Bresenhams algorithm. 
	// Every time there is a primary data point, collect a
	// moment ( in seconds ) and use that as the x coordinate for the 
	// linear regression fit. 

	var today = new Time.Moment(Time.today().value()); 

    function compute(info) {
        // See Activity.Info in the documentation for available information.
        currentBurnRate = getBurnRate();

		// The simulator is broken.   Generate time.
		if ( do_simulate == 1 ) { sim_ut++; } 

		// Try to capture a primary data point.
		{
			var now = System.getTimer();
			var duration = now - pdp_sample_time_last_ms;
			pdp_sample_time_last_ms = now;
			pdp_sample_interpolater -= duration; // Use Bresenhams Algorithm.
		} 

		if (pdp_sample_interpolater >= 0 )  { 
			System.print("Sample ");
			return;
			}
		else {
			pdp_sample_interpolater += pdp_sample_interval_ms; // Reset!
			System.println("Sample PDP Add " + pdp_data_i ); 
		}

		// Now decide whether or not to keep the sample.
		// if things are plugged in, no. FIXME 
		// RS: Maybe this isn't necessary if the app simply declines 
		// to show bogus data. 
		var systemStats = System.getSystemStats();
		var battery = systemStats == null ? null : systemStats.battery;
		if ( battery == null ) { return; }

		var index = pdp_data_i & 0xF;

		var now_ut = new Time.Moment(Time.today().value()); 

		// Detect the first point and fake it.   Otherwise 
		// advance time by 1s/s 
		if ( do_simulate == 1 ) {
			pdp_data_time_ut[index] = sim_ut; 
		} else {
			pdp_data_time_ut[index] = now_ut.value();
			}	

		pdp_data_battery[index] = battery;
		pdp_data_i++;

		extrapolate();
    }
    
   //! Display the value you computed here. This will be called
    //! once a second when the data field is visible.
    function onUpdate(dc)
    {
	    var dataColor;
	    
        var label = View.findDrawableById("label");
        label.setText("Burn rate %/hour");
	    if (getBackgroundColor() == Graphics.COLOR_BLACK) {
	        label.setColor(Graphics.COLOR_WHITE);
			dataColor = Graphics.COLOR_WHITE;
	    } else {
	        label.setColor(Graphics.COLOR_BLACK);
			dataColor = Graphics.COLOR_BLACK;
		}
		var burnRateIsString = currentBurnRate instanceof String;
	    if (!(currentBurnRate instanceof String) && currentBurnRate > veryHighBurnRate) {
	    	dataColor = Graphics.COLOR_RED;
    	}
        View.findDrawableById("Background").setColor(getBackgroundColor());
        var value = View.findDrawableById("value");
        value.setColor(dataColor);
        if (!(currentBurnRate instanceof String)) {
			var burnRateString = currentBurnRate.format("%.1f") + "%";
	        value.setText(burnRateString);
        } else {
        	value.setText(currentBurnRate);
    	}
        View.onUpdate(dc);
	}    

	function convertSecondsForLookup(seconds) {
		if (lowMemoryMode) {
			return seconds/lowMemoryDivisor;
		} else {
			return seconds;
		}
	}
	 	
	function getBurnRate() {
		var timeInMs = System.getTimer();
		var seconds = (timeInMs - me.startingTimeInMs) / 1000;
		var currentHourSecond = seconds % self.secondsInHour; 
		var currentHour = seconds / self.secondsInHour;
		var systemStats = System.getSystemStats();
		var battery = systemStats == null ? null : systemStats.battery;
		var burnRate = 0;
		if (battery != null) {
			var effectiveHourSecond = convertSecondsForLookup(currentHourSecond);
			if (seconds < me.secondsInHour) {
				if (seconds < me.warmupTime) {
					burnRate = "Calculating...";
					getBurnRateFirstHour(convertSecondsForLookup(seconds), battery);
				} else {
					burnRate = getBurnRateFirstHour(convertSecondsForLookup(seconds), battery);
				}
			} else {
				burnRate = getBurnRateLaterHours(effectiveHourSecond, currentHour, battery);		
			}
			self.timesForBattery[effectiveHourSecond] = currentHour;
			self.batteryValues[effectiveHourSecond] = battery;			
		}
		if (burnRate != 0) {
			me.lastBurnRate = burnRate;
		} else {
			burnRate = me.lastBurnRate;
		}
		return burnRate;
	}

	function getBurnRateFirstHour(seconds, battery) {
		if (seconds == 0) {
			return 0;
		} 
		if (batteryValues[0] == null) {
			System.println("No initial battery value at " + seconds);
			batteryValues[0] = battery;
			timesForBattery[0] = 0;
			return 0;
		}
		var drainFromStart = batteryValues[0] - battery;
		return (secondsInHour * drainFromStart) / seconds;
	}

	function findClosestBatteryValue(seconds) {
		for (var where = 0; where < 5 && seconds >= where; ++where) {
			if (batteryValues[seconds-where] != null && timesForBattery[seconds-where] != null) {
				return [ timesForBattery[seconds-where], me.batteryValues[seconds-where] ];
			}
		}
		return null;
	} 
	
	function getBurnRateLaterHours(seconds, currentHour, battery) {
		var previousBatteryValue = findClosestBatteryValue(seconds);
		if (previousBatteryValue == null) {
			System.println("No battery value at " + seconds + " seconds");
			return me.lastBurnRate;
		}
		var elapsedHours = currentHour - previousBatteryValue[0];
		if (elapsedHours > 1) {
			var drainPerHour = (previousBatteryValue[1] - battery)/elapsedHours;
			return drainPerHour;
		} else {
			return me.lastBurnRate;
		}
	}	
	
}