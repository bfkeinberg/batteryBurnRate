# BatteryBurn Rate 2.0

This app measures the Battery Burn rate in percent/hour or the charge rate in percent per hour.  

Battery levels change slowly.   The data field collects multiple samples over time in order to produce an accurate estimate of battery discharge or charge rate.   It can take the data field up to an hour to calculate a high accuracy estimate.

## Theory of Operation 

The app collects a timestamped battery level appromimately every four minutes, or whenever the reported battery level changes.

The result is that the estimate is based upon at most one hour of data, or less data if the battery level is changing quickly. 

## Changes

2.0: Overhaul the sampling system and improve the estimation.