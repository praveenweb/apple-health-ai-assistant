CREATE TABLE IF NOT EXISTS app_user (
    id SERIAL PRIMARY KEY,
    sex VARCHAR(50) DEFAULT 'unknown',
    date_of_birth DATE DEFAULT NULL,
    blood_type VARCHAR(50) DEFAULT 'unknown',
    skin_type VARCHAR(50) DEFAULT 'unknown',
    wheelchair_use BOOLEAN DEFAULT NULL,
    cardio_fitness_medications_use VARCHAR(50) DEFAULT 'None'
);

CREATE TABLE IF NOT EXISTS health_data (
    type VARCHAR(255),
    sourceName VARCHAR(255),
    sourceVersion VARCHAR(255) DEFAULT NULL,
    unit VARCHAR(50) DEFAULT NULL,
    creationDate TIMESTAMP,
    startDate TIMESTAMP DEFAULT NULL,
    endDate TIMESTAMP DEFAULT NULL,
    value DECIMAL
);

CREATE TABLE workouts (
    workoutActivityType VARCHAR(255) NOT NULL,
    duration NUMERIC DEFAULT NULL,
    durationUnit VARCHAR(50) DEFAULT NULL,
    totalDistance NUMERIC DEFAULT NULL,
    totalDistanceUnit VARCHAR(50) DEFAULT NULL,
    totalEnergyBurned NUMERIC DEFAULT NULL,
    totalEnergyBurnedUnit VARCHAR(50) DEFAULT NULL,
    sourceName VARCHAR(255),
    sourceVersion VARCHAR(255),
    device VARCHAR(255),
    creationDate TIMESTAMP WITH TIME ZONE,
    startDate TIMESTAMP WITH TIME ZONE NOT NULL,
    endDate TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE OR REPLACE VIEW distinct_measurement_types AS
    SELECT type,
    COUNT(*) AS type_count
    FROM health_data
    GROUP BY type;

CREATE OR REPLACE VIEW distinct_units AS
SELECT health_data.unit,
    count(*) AS unit_count
   FROM health_data
  GROUP BY health_data.unit;

CREATE OR REPLACE VIEW sources AS
    SELECT sourcename,
    COUNT(*) AS records_count
    FROM health_data
    GROUP BY sourcename; 

CREATE OR REPLACE VIEW daily_stand_hours AS
    WITH StandHourCTE AS (
    SELECT
        type,
        sourcename,
        sourceversion,
        unit,
        creationdate,
        startdate,
        enddate,
        value,
        DATE_TRUNC('hour', startdate) AS stand_hour
    FROM
        health_data
    WHERE
        type = 'AppleStandTime'
    ),
    DistinctStandHours AS (
        SELECT
            DATE_TRUNC('day', stand_hour) AS stand_day,  -- Truncate to day level
            stand_hour,
            sourcename
        FROM
            StandHourCTE
        GROUP BY
            stand_day, stand_hour, sourcename
    )
    SELECT
        stand_day,
        sourcename,
        COUNT(DISTINCT stand_hour) AS stand_hours_per_day  -- Count unique stand hours per day
    FROM
        DistinctStandHours
    GROUP BY
        stand_day, sourcename
    ORDER BY
        stand_day desc;

CREATE OR REPLACE VIEW daily_standing_minutes AS
    WITH StandMinutesCTE AS (
    SELECT
        type,
        sourcename,
        sourceversion,
        unit,
        creationdate,
        startdate,
        enddate,
        value,
        DATE_TRUNC('day', startdate) AS stand_day  -- Truncate startdate to the day level
    FROM
        health_data
    WHERE
        type = 'AppleStandTime'
    )
    SELECT
        stand_day,
        SUM(value) AS total_standing_minutes  -- Sum of standing minutes per day
    FROM
        StandMinutesCTE
    GROUP BY
        stand_day
    ORDER BY
        stand_day desc;

CREATE OR REPLACE VIEW daily_exercise_minutes AS
    WITH ExerciseMinutesCTE AS (
    SELECT
        type,
        sourcename,
        sourceversion,
        unit,
        creationdate,
        startdate,
        enddate,
        value,
        DATE_TRUNC('day', startdate) AS exercise_date  -- Truncate startdate to the day level
    FROM
        health_data
    WHERE
        type = 'AppleExerciseTime'
    )
    SELECT
        exercise_date,
        SUM(value) AS daily_exercise_minutes  -- Sum of exercise minutes per day
    FROM
        ExerciseMinutesCTE
    GROUP BY
        exercise_date
    ORDER BY
        exercise_date desc;

CREATE OR REPLACE VIEW daily_basal_energy_burned AS
    WITH BasalEnergyBurnedCTE AS (
    SELECT
        type,
        sourcename,
        sourceversion,
        unit,
        creationdate,
        startdate,
        enddate,
        value,
        DATE_TRUNC('day', startdate) AS burn_date  -- Truncate startdate to the day level
    FROM
        health_data
    WHERE
        type = 'BasalEnergyBurned'
    )
    SELECT
        burn_date,
        unit,
        SUM(value) AS daily_basal_energy_burned  -- Sum of basal energy burned per day
    FROM
        BasalEnergyBurnedCTE
    GROUP BY
        burn_date, unit
    ORDER BY
        burn_date desc;

CREATE OR REPLACE VIEW daily_max_audio_exposure_dbaspl_levels AS
    WITH HeadphoneAudioExposureCTE AS (
    SELECT
        type,
        sourcename,
        sourceversion,
        unit,
        creationdate,
        startdate,
        enddate,
        value,
        DATE_TRUNC('day', startdate) AS exposure_date  -- Truncate startdate to the day level
    FROM
        health_data
    WHERE
        type = 'HeadphoneAudioExposure'
    )
    SELECT
        exposure_date,
        unit,
        MAX(value) AS daily_max_exposure_levels  -- Max dBASPL levels
    FROM
        HeadphoneAudioExposureCTE
    GROUP BY
        exposure_date, unit
    ORDER BY
        daily_max_exposure_levels desc;

CREATE OR REPLACE VIEW daily_flights_climbed AS
    WITH DailyFlightsClimbedCTE AS (
    SELECT
        type,
        sourcename,
        sourceversion,
        unit,
        creationdate,
        startdate,
        enddate,
        value,
        DATE_TRUNC('day', startdate) AS climb_date  -- Truncate startdate to the day level
    FROM
        health_data
    WHERE
        type = 'FlightsClimbed'
    )
    SELECT
        climb_date,
        SUM(value) AS daily_flights_climbed  -- Daily flights / staircase climbing data
    FROM
        DailyFlightsClimbedCTE
    GROUP BY
        climb_date
    ORDER BY
        climb_date desc;

-- Nutrition Analysis Views
CREATE OR REPLACE VIEW daily_nutrition_summary AS
SELECT 
    DATE_TRUNC('day', startDate) as date,
    ROUND(SUM(CASE WHEN type = 'DietaryEnergyConsumed' THEN value ELSE 0 END)) as total_calories,
    ROUND(SUM(CASE WHEN type = 'DietaryProtein' THEN value ELSE 0 END)) as total_protein,
    ROUND(SUM(CASE WHEN type = 'DietaryCarbohydrates' THEN value ELSE 0 END)) as total_carbs,
    ROUND(SUM(CASE WHEN type = 'DietaryFatTotal' THEN value ELSE 0 END)) as total_fat,
    ROUND(SUM(CASE WHEN type = 'DietaryFiber' THEN value ELSE 0 END)) as total_fiber,
    ROUND(SUM(CASE WHEN type = 'DietarySugar' THEN value ELSE 0 END)) as total_sugar
FROM health_data
GROUP BY DATE_TRUNC('day', startDate)
ORDER BY date DESC;

-- Detailed Fat Breakdown View
CREATE OR REPLACE VIEW daily_fat_composition AS
SELECT 
    DATE_TRUNC('day', startDate) as date,
    ROUND(SUM(CASE WHEN type = 'DietaryFatTotal' THEN value ELSE 0 END)) as total_fat,
    ROUND(SUM(CASE WHEN type = 'DietaryFatSaturated' THEN value ELSE 0 END)) as saturated_fat,
    ROUND(SUM(CASE WHEN type = 'DietaryFatMonounsaturated' THEN value ELSE 0 END)) as monounsaturated_fat,
    ROUND(SUM(CASE WHEN type = 'DietaryFatPolyunsaturated' THEN value ELSE 0 END)) as polyunsaturated_fat
FROM health_data
GROUP BY DATE_TRUNC('day', startDate)
ORDER BY date DESC;

-- Cardiovascular Health Metrics View
CREATE OR REPLACE VIEW daily_cardiovascular_metrics AS
SELECT date_trunc('day'::text, health_data.startdate) AS date,
    round(avg(
        CASE
            WHEN ((health_data.type)::text = 'RestingHeartRate'::text) THEN health_data.value
            ELSE NULL::numeric
        END)) AS resting_heart_rate,
    round(avg(
        CASE
            WHEN ((health_data.type)::text = 'HeartRateVariabilitySDNN'::text) THEN health_data.value
            ELSE NULL::numeric
        END)) AS hrv_sdnn,
    round(avg(
        CASE
            WHEN ((health_data.type)::text = 'OxygenSaturation'::text) THEN health_data.value * 100
            ELSE NULL::numeric
        END), 2) AS avg_oxygen_saturation,
    round(avg(
        CASE
            WHEN ((health_data.type)::text = 'VO2Max') THEN health_data.value
            ELSE NULL::numeric
        END)) AS vo2_max
   FROM health_data
  GROUP BY (date_trunc('day'::text, health_data.startdate))
  ORDER BY (date_trunc('day'::text, health_data.startdate)) DESC;

-- Blood Pressure Tracking View
CREATE OR REPLACE VIEW daily_blood_pressure_summary AS
SELECT 
    DATE_TRUNC('day', startDate) as date,
    ROUND(AVG(CASE WHEN type = 'BloodPressureSystolic' THEN value END)) as avg_systolic,
    ROUND(MIN(CASE WHEN type = 'BloodPressureSystolic' THEN value END)) as min_systolic,
    ROUND(MAX(CASE WHEN type = 'BloodPressureSystolic' THEN value END)) as max_systolic,
    ROUND(AVG(CASE WHEN type = 'BloodPressureDiastolic' THEN value END)) as avg_diastolic,
    ROUND(MIN(CASE WHEN type = 'BloodPressureDiastolic' THEN value END)) as min_diastolic,
    ROUND(MAX(CASE WHEN type = 'BloodPressureDiastolic' THEN value END)) as max_diastolic
FROM health_data
GROUP BY DATE_TRUNC('day', startDate)
ORDER BY date DESC;

-- Walking and Mobility Analysis View
CREATE OR REPLACE VIEW daily_mobility_metrics AS
SELECT 
    DATE_TRUNC('day', startDate) as date,
    ROUND(AVG(CASE WHEN type = 'WalkingSpeed' THEN value END), 2) as avg_walking_speed,
    ROUND(AVG(CASE WHEN type = 'WalkingStepLength' THEN value END), 2) as avg_step_length,
    ROUND(AVG(CASE WHEN type = 'WalkingAsymmetryPercentage' THEN value END), 2) as walking_asymmetry,
    ROUND(AVG(CASE WHEN type = 'WalkingDoubleSupportPercentage' THEN value END), 2) as double_support_percentage,
    ROUND(AVG(CASE WHEN type = 'StairAscentSpeed' THEN value END), 2) as stair_ascent_speed,
    ROUND(AVG(CASE WHEN type = 'StairDescentSpeed' THEN value END), 2) as stair_descent_speed
FROM health_data
GROUP BY DATE_TRUNC('day', startDate)
ORDER BY date DESC;

-- Running Performance Metrics View
CREATE OR REPLACE VIEW running_performance_analysis AS
SELECT 
    DATE_TRUNC('day', startDate) as date,
    ROUND(AVG(CASE WHEN type = 'RunningSpeed' THEN value END), 2) as avg_running_speed,
    ROUND(AVG(CASE WHEN type = 'RunningPower' THEN value END), 2) as avg_running_power,
    ROUND(AVG(CASE WHEN type = 'RunningGroundContactTime' THEN value END), 2) as ground_contact_time,
    ROUND(AVG(CASE WHEN type = 'RunningVerticalOscillation' THEN value END), 2) as vertical_oscillation,
    ROUND(AVG(CASE WHEN type = 'RunningStrideLength' THEN value END), 2) as stride_length
FROM health_data
GROUP BY DATE_TRUNC('day', startDate)
ORDER BY date DESC;

-- Body Composition Tracking View
CREATE OR REPLACE VIEW body_composition_tracking AS
SELECT 
    DATE_TRUNC('day', startDate) as date,
    ROUND(AVG(CASE WHEN type = 'BodyMass' THEN value END), 2) as weight,
    ROUND(AVG(CASE WHEN type = 'BodyFatPercentage' THEN value END), 2) as body_fat_percentage,
    ROUND(AVG(CASE WHEN type = 'LeanBodyMass' THEN value END), 2) as lean_body_mass,
    ROUND(AVG(CASE WHEN type = 'BodyMassIndex' THEN value END), 2) as bmi,
    ROUND(AVG(CASE WHEN type = 'WaistCircumference' THEN value END), 2) as waist_circumference
FROM health_data
GROUP BY DATE_TRUNC('day', startDate)
ORDER BY date DESC;

-- Environmental Exposure View
CREATE OR REPLACE VIEW daily_environmental_exposure AS
SELECT 
    DATE_TRUNC('day', startDate) as date,
    ROUND(SUM(CASE WHEN type = 'TimeInDaylight' THEN value ELSE 0 END)) as daylight_minutes,
    ROUND(MAX(CASE WHEN type = 'EnvironmentalAudioExposure' THEN value END)) as max_environmental_audio_db,
    ROUND(AVG(CASE WHEN type = 'EnvironmentalSoundReduction' THEN value END)) as avg_sound_reduction
FROM health_data
GROUP BY DATE_TRUNC('day', startDate)
ORDER BY date DESC;

-- Respiratory Health Metrics View
CREATE OR REPLACE VIEW respiratory_health_metrics AS
SELECT 
    DATE_TRUNC('day', startDate) as date,
    ROUND(AVG(CASE WHEN type = 'RespiratoryRate' THEN value END), 2) as respiratory_rate,
    ROUND(AVG(CASE WHEN type = 'ForcedVitalCapacity' THEN value END), 2) as vital_capacity,
    ROUND(AVG(CASE WHEN type = 'ForcedExpiratoryVolume1' THEN value END), 2) as fev1,
    ROUND(AVG(CASE WHEN type = 'OxygenSaturation' THEN value END), 2) as oxygen_saturation
FROM health_data
GROUP BY DATE_TRUNC('day', startDate)
ORDER BY date DESC;

CREATE OR REPLACE VIEW heart_rate_zones_patterns AS
    WITH heart_rate_data AS (
        SELECT 
            DATE_TRUNC('hour', startDate) as hour,
            value as heart_rate,
            CASE 
                WHEN value < 60 THEN 'Rest Zone (<60 bpm)'
                WHEN value < 100 THEN 'Light Activity (60-100 bpm)'
                WHEN value < 140 THEN 'Cardio Zone (100-140 bpm)'
                ELSE 'Peak Zone (>140 bpm)'
            END as heart_rate_zone
        FROM health_data
        WHERE type = 'HeartRate'
    )
    SELECT 
        hour,
        heart_rate_zone,
        COUNT(*) as measurements,
        ROUND(AVG(heart_rate), 1) as avg_heart_rate,
        ROUND(MIN(heart_rate), 1) as min_heart_rate,
        ROUND(MAX(heart_rate), 1) as max_heart_rate
    FROM heart_rate_data
    GROUP BY hour, heart_rate_zone
    ORDER BY hour DESC, heart_rate_zone;

CREATE OR REPLACE VIEW daily_activity_summary AS
SELECT 
    DATE_TRUNC('day', startDate) as date, sourceName,
    -- Steps
    ROUND(SUM(CASE WHEN type = 'StepCount' THEN value ELSE 0 END)) as total_steps,
    -- Calories
    ROUND(SUM(CASE WHEN type = 'ActiveEnergyBurned' THEN value ELSE 0 END), 2) as active_calories,
    ROUND(SUM(CASE WHEN type = 'BasalEnergyBurned' THEN value ELSE 0 END), 2) as basal_calories,
    -- Exercise
    ROUND(SUM(CASE WHEN type = 'AppleExerciseTime' THEN value ELSE 0 END)) as exercise_minutes
FROM health_data
GROUP BY DATE_TRUNC('day', startDate), sourceName
ORDER BY date DESC;

CREATE OR REPLACE VIEW daily_sleep_analysis AS
SELECT 
    "type",
    DATE_TRUNC('day', "startdate" - INTERVAL '6 hours') AS night_date,
    CASE 
        WHEN "value" = 0 THEN 'AsleepDeep'
        WHEN "value" = 1 THEN 'AsleepCore'
        WHEN "value" = 2 THEN 'AsleepREM'
        WHEN "value" = 3 THEN 'InBed'
        WHEN "value" = 4 THEN 'Awake'
        ELSE 'Unknown'
    END AS sleep_stage,
    SUM(EXTRACT(EPOCH FROM ("enddate" - "startdate"))) AS duration_seconds,
    ROUND(SUM(EXTRACT(EPOCH FROM ("enddate" - "startdate"))) / 60, 2) AS duration_minutes,
    ROUND(SUM(EXTRACT(EPOCH FROM ("enddate" - "startdate"))) / 3600, 2) AS duration_hours
FROM 
    "health_data"
WHERE 
    "type" ILIKE '%%SleepAnalysisTimes-%%' 
    -- Capture records starting after 6 PM or ending before 11 AM for a night-to-morning sleep period
    AND (
        ("startdate"::time >= '18:00:00') 
        OR ("enddate"::time <= '11:00:00')
    )
GROUP BY 
    "type", night_date, sleep_stage
ORDER BY 
   night_date desc, type, sleep_stage;

-- Indexes for optimization

-- Index for startDate to improve date range queries
CREATE INDEX idx_health_data_startDate ON health_data(startDate);

-- Index for endDate to improve date range queries
CREATE INDEX idx_health_data_endDate ON health_data(endDate);

-- Index for type column to speed up queries filtering by type
CREATE INDEX idx_health_data_type ON health_data(type);

-- Composite index for queries involving type, startDate, and endDate together
CREATE INDEX idx_health_data_type_start_end ON health_data(type, startDate, endDate);