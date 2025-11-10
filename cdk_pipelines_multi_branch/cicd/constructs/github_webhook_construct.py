"""
CDK Construct for GitHub webhook handler infrastructure.
Creates API Gateway, Lambda function, and EventBridge integration.
"""
from os import path
from typing import Optional

from aws_cdk import (
    Duration,
    RemovalPolicy,
    aws_apigateway as apigw,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct
from cdk_nag import NagSuppressions


class GitHubWebhookConstruct(Construct):
    """
    Construct that creates GitHub webhook handler infrastructure.
    
    Components:
    - API Gateway REST API for webhook endpoint
    - Lambda function to validate and process webhooks
    - Secrets Manager secret for webhook secret
    - EventBridge rules to route events to branch handlers
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        create_branch_function: lambda_.IFunction,
        destroy_branch_function: lambda_.IFunction,
        event_bus_name: str = 'default',
        **kwargs
    ) -> None:
        """
        Initialize the GitHub webhook construct.
        
        Args:
            scope: CDK scope
            construct_id: Construct ID
            create_branch_function: Lambda function to handle branch creation
            destroy_branch_function: Lambda function to handle branch deletion
            event_bus_name: EventBridge event bus name (default: 'default')
        """
        super().__init__(scope, construct_id, **kwargs)
        
        # Create webhook secret in Secrets Manager
        self.webhook_secret = secretsmanager.Secret(
            self,
            'GitHubWebhookSecret',
            secret_name='github-webhook-secret',
            description='Secret for validating GitHub webhook signatures',
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{}',
                generate_string_key='secret',
                exclude_punctuation=True,
                password_length=32
            ),
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Suppress CDK Nag warnings for webhook secret
        NagSuppressions.add_resource_suppressions(
            self.webhook_secret,
            [
                {
                    'id': 'AwsSolutions-SMG4',
                    'reason': 'Webhook secret rotation is not required for this use case.'
                }
            ]
        )
        
        # Create Lambda function for webhook handler
        webhook_handler_dir = path.join(path.dirname(path.dirname(__file__)), 'code')
        
        self.webhook_handler = lambda_.Function(
            self,
            'GitHubWebhookHandler',
            runtime=lambda_.Runtime.PYTHON_3_9,
            function_name='GitHubWebhookHandler',
            handler='github_webhook_handler.handler',
            code=lambda_.Code.from_asset(webhook_handler_dir),
            timeout=Duration.seconds(30),
            environment={
                'WEBHOOK_SECRET_NAME': self.webhook_secret.secret_name,
                'EVENT_BUS_NAME': event_bus_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        # Grant Lambda permission to read webhook secret
        self.webhook_secret.grant_read(self.webhook_handler)
        
        # Grant Lambda permission to publish to EventBridge
        self.webhook_handler.add_to_role_policy(
            iam.PolicyStatement(
                actions=['events:PutEvents'],
                resources=[f'arn:aws:events:{scope.region}:{scope.account}:event-bus/{event_bus_name}']
            )
        )
        
        # Suppress CDK Nag warnings for Lambda
        NagSuppressions.add_resource_suppressions(
            self.webhook_handler,
            [
                {
                    'id': 'AwsSolutions-L1',
                    'reason': 'Python 3.9 is a supported and stable runtime version.'
                }
            ]
        )
        
        # Create API Gateway REST API
        self.api = apigw.RestApi(
            self,
            'GitHubWebhookAPI',
            rest_api_name='github-webhook-api',
            description='API Gateway for receiving GitHub webhooks',
            deploy_options=apigw.StageOptions(
                stage_name='prod',
                throttling_rate_limit=10,
                throttling_burst_limit=20,
                logging_level=apigw.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            ),
            cloud_watch_role=True,
            endpoint_types=[apigw.EndpointType.REGIONAL]
        )
        
        # Create Lambda integration
        webhook_integration = apigw.LambdaIntegration(
            self.webhook_handler,
            proxy=True,
            allow_test_invoke=False
        )
        
        # Add webhook resource and POST method
        webhook_resource = self.api.root.add_resource('webhook')
        webhook_resource.add_method(
            'POST',
            webhook_integration,
            api_key_required=False
        )
        
        # Suppress CDK Nag warnings for API Gateway
        NagSuppressions.add_resource_suppressions(
            self.api,
            [
                {
                    'id': 'AwsSolutions-APIG1',
                    'reason': 'Access logging not required for webhook endpoint.'
                },
                {
                    'id': 'AwsSolutions-APIG2',
                    'reason': 'Request validation not required for webhook endpoint.'
                },
                {
                    'id': 'AwsSolutions-APIG3',
                    'reason': 'WAF not required for webhook endpoint with signature validation.'
                },
                {
                    'id': 'AwsSolutions-APIG4',
                    'reason': 'Authorization handled via webhook signature validation.'
                },
                {
                    'id': 'AwsSolutions-COG4',
                    'reason': 'Cognito not required - using webhook signature validation.'
                }
            ],
            apply_to_children=True
        )
        
        # Create EventBridge rules to route events to Lambda functions
        
        # Rule for branch creation events
        branch_create_rule = events.Rule(
            self,
            'GitHubBranchCreateRule',
            event_pattern=events.EventPattern(
                source=['github.webhook'],
                detail_type=['GitHub Branch Create']
            ),
            event_bus=events.EventBus.from_event_bus_name(
                self, 'EventBus', event_bus_name
            )
        )
        
        branch_create_rule.add_target(
            targets.LambdaFunction(create_branch_function)
        )
        
        # Rule for branch deletion events
        branch_delete_rule = events.Rule(
            self,
            'GitHubBranchDeleteRule',
            event_pattern=events.EventPattern(
                source=['github.webhook'],
                detail_type=['GitHub Branch Delete']
            ),
            event_bus=events.EventBus.from_event_bus_name(
                self, 'EventBus2', event_bus_name
            )
        )
        
        branch_delete_rule.add_target(
            targets.LambdaFunction(destroy_branch_function)
        )
        
        # Store webhook URL as property
        self.webhook_url = f"{self.api.url}webhook"
    
    @property
    def webhook_endpoint_url(self) -> str:
        """Get the webhook endpoint URL."""
        return self.webhook_url
