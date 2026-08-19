import json
import urllib.request
import urllib.error
import os

# AWS Parameters and Secrets Lambda Extension HTTP endpoint
SECRETS_EXTENSION_HTTP_PORT = "2773"
SECRETS_EXTENSION_SERVER_PORT = os.environ.get(
    'PARAMETERS_SECRETS_EXTENSION_HTTP_PORT',
    SECRETS_EXTENSION_HTTP_PORT
)


def get_secret(secret_name):
    """Retrieve secret using AWS Parameters and Secrets Lambda Extension."""
    secrets_extension_endpoint = (
        f"http://localhost:{SECRETS_EXTENSION_SERVER_PORT}"
        f"/secretsmanager/get?secretId={secret_name}"
    )

    # Add authentication header for the extension
    headers = {
        'X-Aws-Parameters-Secrets-Token': os.environ.get('AWS_SESSION_TOKEN', '')
    }

    try:
        req = urllib.request.Request(
            secrets_extension_endpoint,
            headers=headers
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            secret_data = response.read().decode('utf-8')
            return json.loads(secret_data)
    except urllib.error.URLError as e:
        print(f"Error retrieving secret from extension: {e}")
        raise
    except json.JSONDecodeError as e:
        print(f"Error parsing secret JSON: {e}")
        raise
    except Exception as e:
        print(f"Unexpected error in get_secret: {e}")
        raise


def lambda_handler(event, context):
    """Main Lambda function handler."""
    secret_name = os.environ.get('SECRET_NAME')

    if not secret_name:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'SECRET_NAME environment variable not set'
            })
        }

    try:
        # Retrieve secret using the extension
        print(f"Attempting to retrieve secret: {secret_name}")
        secret_response = get_secret(secret_name)
        secret_value = json.loads(secret_response['SecretString'])

        # Use secret values (example: database connection info)
        db_host = secret_value.get('database_host', 'Not found')
        db_name = secret_value.get('database_name', 'Not found')
        username = secret_value.get('username', 'Not found')

        print(f"Successfully retrieved secret for database: {db_name}")

        # In a real application, you would use these values to connect
        # to your database or external service
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Secret retrieved successfully',
                'database_host': db_host,
                'database_name': db_name,
                'username': username,
                'extension_cache': 'Enabled with 300s TTL',
                'note': 'Password retrieved but not displayed for security'
            })
        }

    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'details': str(e)
            })
        }
