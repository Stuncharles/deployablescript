# Use an official Python image (adjust to your app language)
FROM python:3.12-slim

# Set working directory
WORKDIR /app

# Copy app files
COPY . /app

# Install dependencies (adjust if using Node, Java, etc.)
RUN pip install --no-cache-dir -r requirements.txt

# Expose the port the app listens on
EXPOSE 8080

# Run the application
CMD ["python", "app.py"]
