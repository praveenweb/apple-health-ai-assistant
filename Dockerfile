# Use an official lightweight Python image
FROM python:3.11-slim

# Install PostgreSQL development libraries and GCC, then clean up apt cache
RUN apt-get update && apt-get install -y \
    libpq-dev gcc && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Copy and install Python dependencies separately to leverage caching
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy the remaining application files
COPY parse.py formatters.py schema.sql export.zip .env /app/

# Run the Python script
CMD ["python", "parse.py"]
