	(:test)
	function testAfterOneHour(logger) {
		var view = new BatteryBurnMock();
		for (var ind = 0; ind < view.secondsInHour; ++ind) {
			view.batteryValues[ind] = 99;
		}
		logger.debug("done initializing");
		return view.batteryValues[2500] != null;
	}
