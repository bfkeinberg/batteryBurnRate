using Toybox.WatchUi;
using Toybox.System;
using Toybox.Test;

class BatteryBurnRateView extends WatchUi.SimpleDataField {
	const secondsInHour = 3600;
	var batteryValues = new [secondsInHour];
	var startingTimeInMs;
	var lastBurnRate;
	
    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();
        label = "Burn rate %/hour";
        startingTimeInMs = System.getTimer();
        lastBurnRate = 0;
    }

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info) {
        // See Activity.Info in the documentation for available information.
        return getBurnRate();
    }

	function getBurnRate() {
		var timeInMs = System.getTimer();
		var seconds = (timeInMs - me.startingTimeInMs) / 1000;
		var currentHourSecond = seconds % self.secondsInHour; 
		var battery = System.getSystemStats().battery;
		var burnRate = null;
		if (battery != null) {
			if (seconds < me.secondsInHour) {
				burnRate = getBurnRateFirstHour(seconds, battery);
			}
			else {
				burnRate = getBurnRateLaterHours(currentHourSecond, battery);		
			}
			me.batteryValues[currentHourSecond] = battery;
			if (burnRate != 0) {
				me.lastBurnRate = burnRate;
			}
		}
		return burnRate;
	}

	function getBurnRateFirstHour(seconds, battery) {
		if (seconds == 0) {
			return 0;
		} 
		if (me.batteryValues[0] == null) {
			System.println("No initial battery value");
			return 0;
		}
		var drainFromStart = me.batteryValues[0] - battery;
		return (secondsInHour * drainFromStart) / seconds;
	}

	function findClosestBatteryValue(seconds) {
		for (var where = 0; where < 5 && seconds >= where; ++where) {
			if (me.batteryValues[seconds-where] != null) {
				return me.batteryValues[seconds-where];
			}
		}
		return null;
	} 
	
	function getBurnRateLaterHours(seconds, battery) {
		var previousBatteryValue = findClosestBatteryValue(seconds);
		if (previousBatteryValue == null) {
			System.println("No battery value at " + seconds + " seconds");
			return me.lastBurnRate;
		}
		var drainPerHour = previousBatteryValue - battery;
		return drainPerHour;
	}	
	
}