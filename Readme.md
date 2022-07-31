# BatteryBurn Rate 2.0

This app measures the discharge or charge rate of your battery in percent per hour.  

Battery levels change slowly.   The data field collects multiple samples over time in order to produce an accurate estimate of battery discharge or charge rate.   It can take the data field up to an hour to calculate a high accuracy estimate.   Estimating battery charge requires specialized devices and software.   

This data field estimates battery consumption based upon the readings from your devices build-in battery monitoring circuits which have their own error.   Its an estimate based upon an estimate.

## How to use

The data field runs automatically and resets the estimate when you charge your device or unplug a charger.
It will display -wait- until there has been a battery level change. 

If your device is discharging slowly or doesn't have many battery levels this may take a while.


## Theory of Operation 

The app collects a timestamped battery level appromimately every four minutes, or whenever the reported battery level changes.  The data field uses all of the samples to estimate the true rate.

The estimate is based upon at most one hour of data, or less data if the battery level is changing quickly. 

## Using the data field to collect data 

*Nerd Alert*

The data field can be used to collect battery performance data.   Every time the battery level changes the
data field writes a single line with time, battery level, and charge/discharge status 

Example data file:
```
# BatteryBurnRate Started 2022-JUL-14 19:28:26
# time(h), time(s), battery level, charging(Y/N)
0.000278,1,90.000000,N
0.179722,647,89.000000,N
0.513056,1847,88.000000,N
0.829722,2987,87.000000,N
1.046389,3767,86.000000,N
1.346389,4847,85.000000,N
1.563056,5627,84.000000,N
```



## Changes

2.0: Overhaul the sampling system and improve the estimation.
2.1: Cleanup the logging so that it can be used for data collection.
