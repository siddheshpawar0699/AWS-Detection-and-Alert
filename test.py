import base64
import boto3
import time
from botocore.exceptions import ClientError

rekognition_client = boto3.client('rekognition', region_name='us-east-1')

rekognition_collection_name = "felon_images"

try:
    rekognition_client.delete_collection(CollectionId=rekognition_collection_name)

    
except ClientError as e:
    if e.response['Error']['Code'] == 'ResourceAlreadyExistsException':
        pass  # Collection already exists
    else:
        raise