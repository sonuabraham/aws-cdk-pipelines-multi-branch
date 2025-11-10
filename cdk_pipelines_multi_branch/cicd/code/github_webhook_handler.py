"""
Lambda function to receive and validate GitHub webhooks for branch events.
Publishes custom events to EventBridge for branch creation/deletion.
"""
import json
import logging
import os
import hmac
import hashlib
import boto3
from typing import Dict, Any, Optional

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
events_client = boto3.client('events')
secretsmanager_client = boto3.client('secretsmanager')

# Environment variables
EVENT_BUS_NAME = os.environ.get('EVENT_BUS_NAME', 'default')
WEBHOOK_SECRET_NAME = os.environ['WEBHOOK_SECRET_NAME']

# Cache for webhook secret
_webhook_secret_cache: Optional[str] = None


def get_webhook_secret() -> str:
    """Retrieve webhook secret from AWS Secrets Manager with caching."""
    global _webhook_secret_cache
    
    if _webhook_secret_cache is None:
        try:
            response = secretsmanager_client.get_secret_value(
                SecretId=WEBHOOK_SECRET_NAME
            )
            _webhook_secret_cache = response['SecretString']
            logger.info("Webhook secret retrieved from Secrets Manager")
        except Exception as e:
            logger.error(f"Failed to retrieve webhook secret: {e}")
            raise
    
    return _webhook_secret_cache


def validate_github_signature(payload: bytes, signature: str, secret: str) -> bool:
    """
    Validate GitHub webhook signature using HMAC SHA256.
    
    Args:
        payload: Raw request body as bytes
        signature: GitHub signature from X-Hub-Signature-256 header
        secret: Webhook secret
        
    Returns:
        True if signature is valid, False otherwise
    """
    if not signature or not signature.startswith('sha256='):
        logger.warning("Invalid signature format")
        return False
    
    expected_signature = 'sha256=' + hmac.new(
        secret.encode('utf-8'),
        payload,
        hashlib.sha256
    ).hexdigest()
    
    # Use constant-time comparison to prevent timing attacks
    is_valid = hmac.compare_digest(expected_signature, signature)
    
    if not is_valid:
        logger.warning("Signature validation failed")
    
    return is_valid


def parse_github_event(headers: Dict[str, str], body: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Parse GitHub webhook payload for branch create/delete events.
    
    Args:
        headers: Request headers
        body: Parsed JSON body
        
    Returns:
        Parsed event data or None if not a branch event
    """
    github_event = headers.get('X-GitHub-Event', headers.get('x-github-event', ''))
    
    # Handle branch creation
    if github_event == 'create':
        ref_type = body.get('ref_type')
        if ref_type == 'branch':
            return {
                'eventType': 'create',
                'referenceType': 'branch',
                'referenceName': body.get('ref'),
                'repositoryName': body.get('repository', {}).get('full_name'),
                'sender': body.get('sender', {}).get('login'),
                'timestamp': body.get('repository', {}).get('updated_at')
            }
    
    # Handle branch deletion
    elif github_event == 'delete':
        ref_type = body.get('ref_type')
        if ref_type == 'branch':
            return {
                'eventType': 'delete',
                'referenceType': 'branch',
                'referenceName': body.get('ref'),
                'repositoryName': body.get('repository', {}).get('full_name'),
                'sender': body.get('sender', {}).get('login'),
                'timestamp': body.get('repository', {}).get('updated_at')
            }
    
    # Handle push events (can also indicate branch creation)
    elif github_event == 'push':
        # Check if this is a branch creation (created flag is true)
        if body.get('created'):
            ref = body.get('ref', '')
            if ref.startswith('refs/heads/'):
                branch_name = ref.replace('refs/heads/', '')
                return {
                    'eventType': 'create',
                    'referenceType': 'branch',
                    'referenceName': branch_name,
                    'repositoryName': body.get('repository', {}).get('full_name'),
                    'sender': body.get('sender', {}).get('login'),
                    'timestamp': body.get('repository', {}).get('updated_at')
                }
        # Check if this is a branch deletion (deleted flag is true)
        elif body.get('deleted'):
            ref = body.get('ref', '')
            if ref.startswith('refs/heads/'):
                branch_name = ref.replace('refs/heads/', '')
                return {
                    'eventType': 'delete',
                    'referenceType': 'branch',
                    'referenceName': branch_name,
                    'repositoryName': body.get('repository', {}).get('full_name'),
                    'sender': body.get('sender', {}).get('login'),
                    'timestamp': body.get('repository', {}).get('updated_at')
                }
    
    logger.info(f"Event {github_event} is not a branch create/delete event")
    return None


def publish_to_eventbridge(event_data: Dict[str, Any]) -> None:
    """
    Publish custom event to EventBridge.
    
    Args:
        event_data: Parsed event data
    """
    try:
        detail_type = f"GitHub Branch {event_data['eventType'].capitalize()}"
        
        response = events_client.put_events(
            Entries=[
                {
                    'Source': 'github.webhook',
                    'DetailType': detail_type,
                    'Detail': json.dumps({
                        'referenceType': event_data['referenceType'],
                        'referenceName': event_data['referenceName'],
                        'repositoryName': event_data['repositoryName'],
                        'sender': event_data['sender'],
                        'timestamp': event_data['timestamp']
                    }),
                    'EventBusName': EVENT_BUS_NAME
                }
            ]
        )
        
        if response['FailedEntryCount'] > 0:
            logger.error(f"Failed to publish event to EventBridge: {response}")
        else:
            logger.info(f"Successfully published {detail_type} event to EventBridge")
            
    except Exception as e:
        logger.error(f"Error publishing to EventBridge: {e}")
        raise


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function handler for GitHub webhooks.
    
    Args:
        event: API Gateway event
        context: Lambda context
        
    Returns:
        API Gateway response
    """
    logger.info(f"Received webhook event: {json.dumps(event)}")
    
    try:
        # Extract request data
        headers = event.get('headers', {})
        body_str = event.get('body', '{}')
        
        # Handle base64 encoded body
        if event.get('isBase64Encoded', False):
            import base64
            body_str = base64.b64decode(body_str).decode('utf-8')
        
        # Get GitHub signature
        signature = headers.get('X-Hub-Signature-256', headers.get('x-hub-signature-256', ''))
        
        # Validate signature
        webhook_secret = get_webhook_secret()
        if not validate_github_signature(body_str.encode('utf-8'), signature, webhook_secret):
            logger.warning("Webhook signature validation failed")
            return {
                'statusCode': 401,
                'body': json.dumps({'message': 'Invalid signature'})
            }
        
        # Parse JSON body
        body = json.loads(body_str)
        
        # Parse GitHub event
        event_data = parse_github_event(headers, body)
        
        if event_data:
            # Publish to EventBridge
            publish_to_eventbridge(event_data)
            
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Event processed successfully'})
            }
        else:
            # Not a branch event, but still return success
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'Event received but not processed (not a branch event)'})
            }
            
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in request body: {e}")
        return {
            'statusCode': 400,
            'body': json.dumps({'message': 'Invalid JSON'})
        }
    except Exception as e:
        logger.error(f"Error processing webhook: {e}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'message': 'Internal server error'})
        }
