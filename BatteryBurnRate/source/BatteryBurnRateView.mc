using Toybox.WatchUi;
using Toybox.System;

class BatteryBurnRateView extends WatchUi.SimpleDataField {
	const secondsInHour = 3600;
	var batteryValues = new [secondsInHour];
	var startingTimeInMs;
	
    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();
        label = "Burn rate %/hour";
        startingTimeInMs = System.getTimer();
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
		}
		return burnRate;
	}

	function getBurnRateFirstHour(seconds, battery) {
		if (seconds == 0) {
			return 0;
		} 
		var drainFromStart = me.batteryValues[0] - battery;
		return (secondsInHour * drainFromStart) / seconds;
	}

	function getBurnRateLaterHours(seconds, battery) {
		Test.assertMessage(me.batteryValues[seconds] != null, "Battery status must be defined");
		var drainPerHour = me.batteryValues[seconds] - battery;
		return drainPerHour;
	}	
	
}