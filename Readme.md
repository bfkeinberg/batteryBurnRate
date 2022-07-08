# BatteryBurn Rate 2.0

This app measures the discharge or charge rate of your battery in percent per hour.  

Battery levels change slowly.   The data field collects multiple samples over time in order to produce an accurate estimate of battery discharge or charge rate.   It can take the data field up to an hour to calculate a high accuracy estimate.

## How to use

The data field runs automatically and resets the estimate when you charge your device or unplug a charger.
It will display -wait- until there has been a battery level change. 

If your device is discharging slowly or doesn't have many battery levels this may take a while.


## Theory of Operation 

The app collects a timestamped battery level appromimately every four minutes, or whenever the reported battery level changes.  The data field uses all of the samples to estimate the true rate.

The estimate is based upon at most one hour of data, or less data if the battery level is changing quickly. 

## Changes

2.0: Overhaul the sampling system and improve the estimation.

