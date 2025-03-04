#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Define log file location
SUITECRM_DIR="/var/www/html/suitecrm"
LOG_FILE="$SUITECRM_DIR/.devcontainer/logs/entrypoint.log"

# Required environment variables
REQUIRED_VARS=("MARIADB_ROOT_PASSWORD" "MARIADB_PORT_NUMBER" "MARIADB_DATABASE" "GIT_USER_NAME" "GIT_USER_EMAIL" "MARIADB_BACKUP_FILE")

# Check if each required environment variable is set
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required environment variable '$var' is not set." >&2
        exit 1
    fi
done

# Redirect stdout and stderr to the log file
exec > "$LOG_FILE" 2>&1 || { echo "Failed to redirect logs to $LOG_FILE"; exit 1; }

# Check if the directory exists
if [ ! -d "$SUITECRM_DIR" ]; then
    echo "The directory /var/www/html/suitecrm does not exist. Exiting."
    exit 1
fi

# Check if vendor directory exists; if not, install Composer dependencies
if [ ! -d "$SUITECRM_DIR/vendor" ]; then
    echo "Installing Composer dependencies..."
    if ! composer install --no-dev --no-interaction --working-dir="$SUITECRM_DIR"; then
        echo "Composer installation failed."
        exit 1
    fi
    echo "Composer dependencies installed."

    # Restore database backup
    echo "Restoring database backup..."
    BACKUP_FILE="$SUITECRM_DIR/.devcontainer/config/db/$MARIADB_BACKUP_FILE"

    # Check if the backup file exists
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "The backup file $MARIADB_BACKUP_FILE doesn't exist in .devcontainer/config/db directory. Exiting."
        exit 1
    fi

    # Unzip and restore the database
    if ! gunzip < "$BACKUP_FILE" | mysql -u root -p"${MARIADB_ROOT_PASSWORD}" -h mariadb -P "${MARIADB_PORT_NUMBER}" "${MARIADB_DATABASE}"; then
        echo "Database restoration failed."
        exit 1
    fi
    echo "Database backup restored."
fi

git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

echo "Adding the right permissions to the SuiteCRM directory..."
chown -R www-data:www-data "$SUITECRM_DIR" && \
find "$SUITECRM_DIR" -type d -exec chmod 775 {} + && \
find "$SUITECRM_DIR" -type f -exec chmod 755 {} + && \
chmod 775 "$SUITECRM_DIR/cache" "$SUITECRM_DIR/custom" "$SUITECRM_DIR/modules" "$SUITECRM_DIR/themes" "$SUITECRM_DIR/data" "$SUITECRM_DIR/upload" && \
chmod 775 "$SUITECRM_DIR/config_override.php" 2>/dev/null && \
echo "Finished adding the right permissions to the SuiteCRM directory."

# Start Apache in the foreground
echo "Starting Apache..."
exec apache2-foreground