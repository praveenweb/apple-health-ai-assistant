from datetime import datetime as dt
from datetime import timedelta
from typing import Any, Union

def AppleStandHourFormatter(record: dict) -> dict:
    unit = record.get("unit", "unit")
    device = record.get("sourceName", "unknown")
    sourceVersion = record.get("sourceVersion", "unknown")
    value = record.get("value", 0)
    if value == "HKCategoryValueAppleStandHourStood":
        value = 1
    elif record.get("value") == "HKCategoryValueAppleStandHourIdle":
        value = 0
    
    return {
        "type": "AppleStandHour",
        "sourceName": device,
        "sourceVersion": sourceVersion,
        "unit": unit, 
        "creationDate": record.get("startDate"),
        "startDate": record.get("startDate"),
        "endDate": record.get("endDate"),
        "value": value,
    }

sleep_states_lookup={
    "HKCategoryValueSleepAnalysisAsleepDeep":0,
    "HKCategoryValueSleepAnalysisAsleepCore":1,
    "HKCategoryValueSleepAnalysisAsleepREM":2,
    #"HKCategoryValueSleepAnalysisAsleepUnspecified":3,
    "HKCategoryValueSleepAnalysisInBed": 3,
    "HKCategoryValueSleepAnalysisAwake":4,
}

sleep_states_short_lookup={
    "HKCategoryValueSleepAnalysisAsleepDeep":"Deep",
    "HKCategoryValueSleepAnalysisAsleepCore":"Core",
    "HKCategoryValueSleepAnalysisAsleepREM":"REM",
    #"HKCategoryValueSleepAnalysisAsleepUnspecified":"Asleep",
    "HKCategoryValueSleepAnalysisInBed": "Asleep",
    "HKCategoryValueSleepAnalysisAwake":"Awake",
}

def SleepAnalysisFormatter(record: dict) -> dict:
    device = record.get("sourceName", "unknown")
    value = sleep_states_lookup.get(record.get("value"),5)

    currentSleepRecord = {
        "type": "SleepAnalysisTimes-{}".format(device),
        "sourceName": device,
        "sourceVersion": record.get("sourceVersion", "unknown"),
        "unit": record.get("unit", "seconds"),
        "creationDate": record.get("creationDate", None),
        "startDate": record.get("startDate", None),
        "endDate": record.get("endDate", None),
        "value": value
    }

    return currentSleepRecord