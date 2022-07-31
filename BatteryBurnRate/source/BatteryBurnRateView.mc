using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Test;
using Toybox.AntPlus;

class BatteryBurnRateView extends WatchUi.DataField {
	const secondsInHour = 3600;
	const warmupTime = 1200;
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
    
	function showRemain(burnRate)
	{
		var systemStats = System.getSystemStats();
		var calculated_remain = View.findDrawableById("remain");
		var burnRateAsNum = burnRate;
		if (burnRate != null && burnRate instanceof String) {
			if (burnRate == "Calculating...") {
				burnRateAsNum = null;
			}
			System.println("burn rate before conversion to float is " + burnRate);
			burnRateAsNum = burnRate.toFloat();
		}
		if (systemStats != null && systemStats.battery != null && burnRateAsNum != null && burnRateAsNum > 0) {
			var calcRemain = systemStats.battery / burnRateAsNum;
			System.println("Time remaining is " + calcRemain + " with battery of " + systemStats.battery + " and burn of " + burnRateAsNum + " rate " + burnRate);
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
		showRemain(currentBurnRate);
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