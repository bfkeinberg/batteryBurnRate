using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Test;
using Toybox.Lang;
using Toybox.Application;

class BatteryBurnRateView extends WatchUi.DataField {
  var regressionMode = false;
  
	const secondsInHour = 3600;
	const veryHighBurnRate = 12;
	const lowMemoryDivisor = 6;
	var batteryValues;
	var timesForBattery;
	var lowMemoryMode = false;	
	
	var startingTimeInMs;
	var lastBurnRate;
	var currentBurnRate;
	
  const updateInterval = 60; // Compute only every x s to save some energy
	const bufferSize = 500;    // Keep 500 values in ring buffer 
	var estimatedBatteryLife = 10*3600; // The covered time span of the ring buffer
	var batteryValuesT = null; // The data structure (time values)
	var batteryValuesY = null; // The data structure (battery values)
	var beta1 = 0.0; // regression coefficient (slope)
	var beta0 = 0.0; // regression coefficient (intercept)
	var etaInHours = 10.0; // initial estimated time until battery dead

    // Set the label of the data field here.
    function initialize() {
        DataField.initialize();
        startingTimeInMs = System.getTimer();
        lastBurnRate = 0;
        currentBurnRate = 0;
  	  	me.regressionMode = Application.Properties.getValue("regressionMode");
	  	  me.estimatedBatteryLife = Application.Properties.getValue("estimatedBatteryLife")*3600;
		// DEBUG as sideloading does not support user-settings
		// me.regressionMode = true;
		// me.estimatedBatteryLife = 10*3600;
  		System.println("me.regressionMode: " + me.regressionMode + ", me.estimatedBatteryLife: " + me.estimatedBatteryLife + ", me.bufferSize: " + me.bufferSize);
      if (me.regressionMode){
        me.batteryValuesT = new [me.bufferSize]; 
        me.batteryValuesY = new [me.bufferSize];
      }
	  	else if (System.getSystemStats().freeMemory > 20000) {
        batteryValues = new [secondsInHour];
        timesForBattery = new [secondsInHour];
  		} else {
        batteryValues = new [secondsInHour/6];
        timesForBattery = new [secondsInHour/6];
        lowMemoryMode = true;		
  		}
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

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info) {
        // See Activity.Info in the documentation for available information.
        currentBurnRate = getBurnRate();
    }
    
   //! Display the value you computed here. This will be called
    //! once a second when the data field is visible.
    function onUpdate(dc)
    {
	    var dataColor;
	    
      var label = View.findDrawableById("label");
      if (regressionMode) {
        label.setText("Burn rate %/hour (ETA)");
      } else {
        label.setText("Burn rate %/hour");
      }
	    if (getBackgroundColor() == Graphics.COLOR_BLACK) {
	        label.setColor(Graphics.COLOR_WHITE);
    			dataColor = Graphics.COLOR_WHITE;
	    } else {
	        label.setColor(Graphics.COLOR_BLACK);
			dataColor = Graphics.COLOR_BLACK;
		}
	    if (currentBurnRate > veryHighBurnRate) {
	    	dataColor = Graphics.COLOR_RED;
    	}
        View.findDrawableById("Background").setColor(getBackgroundColor());
        var value = View.findDrawableById("value");
        value.setColor(dataColor);
		var burnRateString = currentBurnRate.format("%.1f") + "%";
        value.setText(burnRateString);
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
      if (me.regressionMode){
        burnRate = regressBurnRate(seconds, battery);
			} else {
        var effectiveHourSecond = convertSecondsForLookup(currentHourSecond);
        if (seconds < me.secondsInHour) {
          burnRate = getBurnRateFirstHour(convertSecondsForLookup(seconds), battery);
        }
        else {
          burnRate = getBurnRateLaterHours(effectiveHourSecond, currentHour, battery);		
        }
        self.timesForBattery[effectiveHourSecond] = currentHour;
        self.batteryValues[effectiveHourSecond] = battery;
      }
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

	function regressBurnRate(seconds, battery){
		var burnRate = 0.0;
		if (seconds % me.updateInterval  == 0){
			updateEstimator(seconds, battery);
			estimateDrain(seconds, battery);
			burnRate = -me.beta1 * me.secondsInHour; // make negative and per hour
			if (burnRate != 0){
				var correctedBeta0 = me.beta0 - (me.beta0 - me.batteryValuesY[0]); // We canot have more than 100 % of battery
				me.etaInHours = (-correctedBeta0/me.beta1 - seconds)/me.secondsInHour; // intersect line with 0.0 and compute ETA
				me.lastBurnRate = burnRate;
				// Format to distinguish burn-in phase
				me.lastBurnRate = Lang.format("$1$", [me.lastBurnRate.format("%02.1f")]);
				me.etaInHours = Lang.format("$1$", [me.etaInHours.format("%02.1f")]);
			}else{
				me.etaInHours = battery/100.0*(estimatedBatteryLife - seconds).toFloat()/me.secondsInHour; // Show a rough estimate until data is available
				me.lastBurnRate = battery/me.etaInHours;
				// Format to distinguish burn-in phase
				me.lastBurnRate = Lang.format("$1$", [me.lastBurnRate.format("%02d")]);
				me.etaInHours = Lang.format("$1$", [me.etaInHours.format("%02.1f")]);
			}
		}
		// System.println("me.lastBurnRate:" + me.lastBurnRate + " me.etaInHours:" + me.etaInHours);
		return me.lastBurnRate + "(" + me.etaInHours + ")";
		}

	function updateEstimator(seconds, battery){
		/**
		Updates the values in the buffer. 
		The buffer is a ring buffer keeping constant me.bufferSize values, 
		where the buffer covers a configureable time range (me.estimatedBatteryLife).
		**/
		if (battery > 0){ // somethime the device reports zero values which destroys the regression
			var idx = (seconds % me.estimatedBatteryLife).toFloat();  // Binning into the invervals
			idx = (idx / me.estimatedBatteryLife.toFloat() * me.bufferSize.toFloat()).toNumber(); 
			me.batteryValuesT[idx] = seconds.toFloat();
			me.batteryValuesY[idx] = battery.toFloat();
		}
	}

	function estimateDrain(seconds, battery) {
		/*
		Simple regression function.
		It takes the ring buffer and computes a regression line.
		The beta1 in $battery = beta1*t + beta0$ is battery drain.

		See: https://en.wikipedia.org/wiki/Simple_linear_regression#Intuitive_explanation
		*/
		var meanT = 0.0;
		var meanY = 0.0;
		var vals = 0;
		for (var where = 0; where < bufferSize  ; ++where) {
			if (me.batteryValuesT[where] != null) {
				meanT = meanT +  me.batteryValuesT[where]; 
				meanY = meanY +  me.batteryValuesY[where]; 
				vals = vals + 1;
			}
		}
		meanT = meanT / vals;
		meanY = meanY / vals;
		if (vals < 2){
			System.println("Not enough values.");
			return;
		}
		var beta1 = 0.0;
		var varianceT = 0.0;
		for (var where = 0; where < bufferSize ; ++where) {
			if (me.batteryValuesT[where] != null) {
					beta1 = beta1 + (me.batteryValuesT[where]-meanT) * (me.batteryValuesY[where]-meanY);
					varianceT = varianceT + (me.batteryValuesT[where]-meanT) * (me.batteryValuesT[where]-meanT);
				}
		}
		me.beta1 = beta1/varianceT;
		me.beta0  = meanY - me.beta1*meanT;
		// System.println("me.beta1:"+ me.beta1 + " me.beta0: " + me.beta0);
		return;			
	}
	
}