import os
import csv
import sys
import json
import time
import psycopg2
import logging
from xml.etree.ElementTree import iterparse
from dotenv import load_dotenv
from shutil import unpack_archive
from typing import List, Dict, Tuple, Any

from formatters import AppleStandHourFormatter, SleepAnalysisFormatter

# Load environment variables from .env file
load_dotenv()

# Get PostgreSQL connection details from environment variables
PG_HOST = os.getenv("PG_HOST")
PG_PORT = os.getenv("PG_PORT")
PG_DATABASE = os.getenv("PG_DATABASE")
PG_USER = os.getenv("PG_USER")
PG_PASSWORD = os.getenv("PG_PASSWORD")

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger()

# Set Globals
# Specify the input XML file and output CSV file
xml_file = 'export/apple_health_export/export.xml'
health_csv_file = 'health.csv'
user_csv_file = 'user.csv'
workout_csv_file = 'workout.csv'
schema_file = 'schema.sql'

def write_to_csv(filename, data, fieldnames, description):
    """
    Write data to a CSV file with error handling.
    
    Args:
        filename (str): Path to the CSV file
        data (list): List of dictionaries containing the data to write
        fieldnames (list): List of column headers
        description (str): Description of the data being written (for logging)
    """
    with open(filename, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        try:
            print(f"{description}")
            writer.writerows(data)
            print(f"Data successfully written to {filename}")
        except Exception as e:
            logger.info(f"Error writing {description.lower()} to CSV: {e}")

def parse_xml_to_csv():
    """
    Parses an Apple Health Export XML file and saves the data to a CSV file.
    """
    records = []
    app_user = []
    workouts = []
    for _, elem in iterparse(xml_file):
        if elem.tag == "Record":
            try:
                # Convert XML attributes to a dictionary and append it to records
                record = elem.attrib
                # Only keep relevant fields
                type = (
                    record.get("type", "Record").removeprefix("HKQuantityTypeIdentifier").removeprefix("HKCategoryTypeIdentifier")
                    .removeprefix("HKDataType")
                )
                ## format and validate some special records
                value = record.get("value")
                if type == "AppleStandHour" or value == "HKCategoryValueAppleStandHourIdle":
                    StandHour = AppleStandHourFormatter(record)
                    records.append(StandHour)
                elif type == "SleepAnalysis":
                    sleep_record = SleepAnalysisFormatter(record)
                    records.append(sleep_record)
                elif value and value.startswith("HKCategoryValue"): 
                    value = 0
                else:
                    filtered_record = {
                        'type': type,
                        'sourceName': record.get('sourceName', "unknown"),
                        'sourceVersion': record.get('sourceVersion'),
                        'unit': record.get('unit', 'unit'),
                        'creationDate': record.get('creationDate'),
                        'startDate': record.get('startDate'),
                        'endDate': record.get('endDate'),
                        'value': value
                    }
                    records.append(filtered_record)
            except Exception as e:
                print(f"Error parsing record: {e}")
                logger.info("Error parsing record data: {e}")
                sys.stdout.flush()
            finally:
                # Clear the element to save memory
                elem.clear()
        elif elem.tag == "Me":
            try:
                current_user = {
                    'sex': elem.attrib.get('HKCharacteristicTypeIdentifierBiologicalSex', 'unknown').removeprefix("HKBiologicalSex"),
                    'date_of_birth': elem.attrib.get('HKCharacteristicTypeIdentifierDateOfBirth', 'unknown'),
                    'blood_type': elem.attrib.get('HKCharacteristicTypeIdentifierBloodType', 'unknown').removeprefix("HKBloodType"),
                    'skin_type': elem.attrib.get('HKCharacteristicTypeIdentifierFitzpatrickSkinType', 'unknown').removeprefix("HKFitzpatrickSkinType"),
                    'wheelchair_use': elem.attrib.get('HKCharacteristicTypeIdentifierWheelchairUse', 'unknown'),
                    'cardio_fitness_medication_use': elem.attrib.get('HKCharacteristicTypeIdentifierCardioFitnessMedicationUse', 'unknown'),
                }
                app_user.append(current_user)
            except Exception as e:
                logger.info(f"Error parsing record: {e}")
            finally:
                # Clear the element to save memory
                elem.clear()
        elif elem.tag == "Workout":
            """Extract all workout data."""
            try:
                workout = elem.attrib
                activityType = workout.get('workoutActivityType').removeprefix("HKWorkoutActivityType")
                workout_data = {
                    'workoutActivityType': activityType,
                    'duration': workout.get('duration'),
                    'durationUnit': workout.get('durationUnit'),
                    'totalDistance': workout.get('totalDistance'),
                    'totalDistanceUnit': workout.get('totalDistanceUnit'),
                    'totalEnergyBurned': workout.get('totalEnergyBurned'),
                    'totalEnergyBurnedUnit': workout.get('totalEnergyBurnedUnit'),
                    'startDate': workout.get('startDate'),
                    'endDate': workout.get('endDate'),
                    'sourceName': workout.get('sourceName'),
                    'sourceVersion': workout.get('sourceVersion'),
                    'device': workout.get('device'),
                    'creationDate': workout.get('creationDate')
                }
                workouts.append(workout_data)
            except Exception as e:
                logger.info(f"Error parsing record: {e}")
            finally:
                # Clear the element to save memory
                elem.clear()
    
    # Define the data structures
    csv_configs = [
        {
            'filename': user_csv_file,
            'data': app_user,
            'fieldnames': ['sex', 'date_of_birth', 'blood_type', 'skin_type', 
                        'wheelchair_use', 'cardio_fitness_medication_use'],
            'description': 'User data'
        },
        {
            'filename': health_csv_file,
            'data': records,
            'fieldnames': ['type', 'sourceName', 'sourceVersion', 'unit', 
                        'creationDate', 'startDate', 'endDate', 'value'],
            'description': 'Health data'
        },
        {
            'filename': workout_csv_file,
            'data': workouts,
            'fieldnames': ['workoutActivityType', 'duration', 'durationUnit', 
                        'totalDistance', 'totalDistanceUnit', 'totalEnergyBurned', 
                        'totalEnergyBurnedUnit', 'sourceName', 'sourceVersion', 
                        'device', 'creationDate', 'startDate', 'endDate'],
            'description': 'Workouts data'
        }
    ]

    # Write all CSV files
    for config in csv_configs:
        write_to_csv(**config)

def initialize_postgres_schema():
    """
    Initializes the PostgreSQL schema by executing the SQL commands in the schema file.
    """
    time.sleep(5)
    # Connect to the PostgreSQL database
    connection = psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        database=PG_DATABASE,
        user=PG_USER,
        password=PG_PASSWORD
    )
    cursor = connection.cursor()
    connection.autocommit = True

    # Load and execute the schema file
    with open(schema_file, 'r') as file:
        schema_sql = file.read()

    # Execute table creation
    cursor.execute(schema_sql)
    connection.commit()

    # Close the cursor and connection
    cursor.close()
    connection.close()

def import_csv_to_postgres(batch_size=100000):
    """
    Optimized function to import data from CSV files into PostgreSQL using:
    - COPY command for initial bulk insert
    - Prepared statements for fallback inserts
    - Efficient batch processing
    - Proper connection management
    """
    connection = psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        database=PG_DATABASE,
        user=PG_USER,
        password=PG_PASSWORD
    )
    try:
        with connection:
            with connection.cursor() as cursor:
                # Import user data first (typically small)
                with open(user_csv_file, 'r') as csvfile:
                    csv_reader = csv.DictReader(csvfile)
                    user_data = []
                    for row in csv_reader:
                        row['wheelchair_use'] = row['wheelchair_use'].lower() == 'true' if row['wheelchair_use'] else None
                        user_data.append((
                            row['sex'],
                            row['date_of_birth'],
                            row['blood_type'],
                            row['skin_type'],
                            row['wheelchair_use'],
                            row['cardio_fitness_medication_use']
                        ))
                    
                    if user_data:
                        cursor.execute(
                            'PREPARE user_insert AS '
                            'INSERT INTO app_user (sex, date_of_birth, blood_type, skin_type, wheelchair_use, cardio_fitness_medications_use) '
                            'VALUES ($1, $2, $3, $4, $5, $6)'
                        )
                        for user in user_data:
                            try:
                                cursor.execute('EXECUTE user_insert (%s, %s, %s, %s, %s, %s)', user)
                                print("User data inserted successfully.")
                            except Exception as e:
                                print(f"Error inserting user data: {e}")
                        cursor.execute('DEALLOCATE user_insert')

                # Import health data using COPY for bulk insert
                try:
                    with open(health_csv_file, 'r') as f:
                        cursor.copy_expert(
                            """
                            COPY health_data (type, sourceName, sourceVersion, unit, creationDate, startDate, endDate, value)
                            FROM STDIN WITH (FORMAT csv, HEADER true)
                            """,
                            f
                        )
                except Exception as e:
                    print(f"Bulk COPY failed, falling back to batch processing: {e}")
                    
                    # Prepare statement for batch processing
                    cursor.execute(
                        'PREPARE health_insert AS '
                        'INSERT INTO health_data (type, sourceName, sourceVersion, unit, creationDate, startDate, endDate, value) '
                        'VALUES ($1, $2, $3, $4, $5, $6, $7, $8)'
                    )
                    
                    # Fallback to batch processing
                    batch = []
                    failed_rows = []
                    
                    with open(health_csv_file, 'r') as csvfile:
                        csv_reader = csv.DictReader(csvfile)
                        for row in csv_reader:
                            batch.append((
                                row['type'],
                                row['sourceName'],
                                row['sourceVersion'],
                                row['unit'],
                                row['creationDate'],
                                row['startDate'],
                                row['endDate'],
                                row['value']
                            ))
                            
                            if len(batch) >= batch_size:
                                failed_rows.extend(process_batch(cursor, batch))
                                batch = []
                        
                        # Process remaining rows
                        if batch:
                            failed_rows.extend(process_batch(cursor, batch))
                    
                    cursor.execute('DEALLOCATE health_insert')
                    
                    # Log failed rows if any
                    if failed_rows:
                        with open('failed_imports.log', 'w') as log:
                            json.dump(failed_rows, log, indent=2)
                        print(f"Failed to import {len(failed_rows)} rows. See failed_imports.log for details.")

                # Import workout data using COPY for bulk insert
                try:
                    with open(workout_csv_file, 'r') as f:
                        cursor.copy_expert(
                            """
                            COPY workouts (workoutActivityType, duration, durationUnit, totalDistance, totalDistanceUnit, 
                                         totalEnergyBurned, totalEnergyBurnedUnit, sourceName, sourceVersion, device, 
                                         creationDate, startDate, endDate)
                            FROM STDIN WITH (FORMAT csv, HEADER true)
                            """,
                            f
                        )
                except Exception as e:
                    print(f"Bulk COPY failed for workout data, falling back to batch processing: {e}")
                    
                    # Prepare statement for batch processing
                    cursor.execute(
                        'PREPARE workout_insert AS '
                        'INSERT INTO workouts (workoutActivityType, duration, durationUnit, totalDistance, totalDistanceUnit, '
                        'totalEnergyBurned, totalEnergyBurnedUnit, sourceName, sourceVersion, device, '
                        'creationDate, startDate, endDate) '
                        'VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)'
                    )
                    
                    # Fallback to batch processing
                    batch = []
                    failed_rows = []
                    
                    with open(workout_csv_file, 'r') as csvfile:
                        csv_reader = csv.DictReader(csvfile)
                        for row in csv_reader:
                            batch.append((
                                row['workoutActivityType'],
                                row['duration'],
                                row['durationUnit'],
                                row['totalDistance'],
                                row['totalDistanceUnit'],
                                row['totalEnergyBurned'],
                                row['totalEnergyBurnedUnit'],
                                row['sourceName'],
                                row['sourceVersion'],
                                row['device'],
                                row['creationDate'],
                                row['startDate'],
                                row['endDate']
                            ))
                            
                            if len(batch) >= batch_size:
                                failed_rows.extend(process_batch(cursor, 'workout_insert', batch))
                                batch = []
                        
                        # Process remaining rows
                        if batch:
                            failed_rows.extend(process_batch(cursor, 'workout_insert', batch))
                    
                    cursor.execute('DEALLOCATE workout_insert')
                    
                    # Log failed rows if any
                    if failed_rows:
                        with open('failed_workout_imports.log', 'w') as log:
                            json.dump(failed_rows, log, indent=2)
                        print(f"Failed to import {len(failed_rows)} workout records. See failed_workout_imports.log for details.")

    finally:
        connection.close()

def process_batch(cursor, batch):
    """
    Process a batch of records using prepared statements.
    Returns a list of failed rows.
    """
    failed_rows = []
    for record in batch:
        try:
            cursor.execute('EXECUTE health_insert (%s, %s, %s, %s, %s, %s, %s, %s)', record)
        except Exception as e:
            failed_rows.append({
                'record': record,
                'error': str(e)
            })
    return failed_rows

if __name__ == "__main__":
    print("Unzipping the export file...")
    try:
        unpack_archive('export.zip', "export")
    except Exception as unzip_err:
        print("Unable to open export zip:", unzip_err)
        exit(1)
    print("Export file unzipped!")

    # First, verify the file exists
    if not os.path.exists(xml_file):
        raise FileNotFoundError(f"XML file not found: {xml_file}")

    # Initialize Postgres tables
    initialize_postgres_schema()
    print("PostgreSQL schema initialized.")

    # Parse XML to CSV
    parse_xml_to_csv()
    print("XML data successfully parsed to CSV.")

    # Import CSV to PostgreSQL
    import_csv_to_postgres()
    print("CSV data successfully imported to PostgreSQL.")