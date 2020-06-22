using Toybox.WatchUi;
using Toybox.System;
using Toybox.Test;
using Toybox.Lang;
using Toybox.Application;

class BatteryBurnRateView extends WatchUi.SimpleDataField {

	var regressionMode = false;
	
	const secondsInHour = 3600;
	var startingTimeInMs;
	var lastBurnRate = 0.0;
	var batteryValues = null;

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
        SimpleDataField.initialize();
		me.regressionMode = Application.Properties.getValue("regressionMode");
		me.estimatedBatteryLife = Application.Properties.getValue("estimatedBatteryLife")*3600;
		// DEBUG as sideloading does not support user-settings
		// me.regressionMode = true;
		// me.estimatedBatteryLife = 10*3600;
		System.println("me.regressionMode: " + me.regressionMode + ", me.estimatedBatteryLife: " + me.estimatedBatteryLife + ", me.bufferSize: " + me.bufferSize);
		if (me.regressionMode){
        	label = "Burn rate %/hour (ETA)";
			me.batteryValuesT = new [me.bufferSize]; 
			me.batteryValuesY = new [me.bufferSize];
		}else{
        	label = "Burn rate %/hour";
			me.batteryValues = new [me.secondsInHour]; // Save some memory
		}
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
			if (me.regressionMode){
				burnRate = regressBurnRate(seconds, battery);
			}
			else{
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