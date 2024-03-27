from __future__ import print_function
import base64
import datetime
import time
from decimal import Decimal
import uuid
import json
import pickle
import boto3
import pytz
from pytz import timezone
from copy import deepcopy
import os

hash = set()

def load_config():
    '''Load configuration from file.'''
    with open('imageprocessor-params.json', 'r') as conf_file:
        conf_json = conf_file.read()
        return json.loads(conf_json)

def convert_ts(ts, config):
    '''Converts a timestamp to the configured timezone. Returns a localized datetime object.'''
    #lambda_tz = timezone('US/Pacific')
    tz = timezone(config['timezone'])
    utc = pytz.utc
    
    utc_dt = utc.localize(datetime.datetime.utcfromtimestamp(ts))

    localized_dt = utc_dt.astimezone(tz)

    return localized_dt


def process_image(event, context):

    #Initialize clients
    rekog_client = boto3.client('rekognition')
    sns_client = boto3.client('sns')
    s3_client = boto3.client('s3')
    dynamodb = boto3.resource('dynamodb')

    #Load config
    config = load_config()

    s3_bucket = config["s3_bucket"]
    s3_key_frames_root = config["s3_key_frames_root"]

    ddb_table = dynamodb.Table(config["ddb_table"])
    ddb_frame_table = dynamodb.Table(config['ddb_input_image_table'])
      
    #### label_watch_sns_topic_arn = config.get("label_watch_sns_topic_arn", "")

    # Retrieve the SNS topic ARN from the environment variable
    label_watch_sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    collection_id = config['rekognition_col_name']

    #Iterate on frames fetched from Kinesis
    for record in event['Records']:

        frame_package_b64 = record['kinesis']['data']
        frame_package = pickle.loads(base64.b64decode(frame_package_b64))

        img_bytes = frame_package["ImageBytes"]
        approx_capture_ts = frame_package["ApproximateCaptureTime"]
        frame_count = frame_package["FrameCount"]
        
        now_ts = time.time()

        frame_id = str(uuid.uuid4())
        processed_timestamp = Decimal(now_ts)
        approx_capture_timestamp = Decimal(approx_capture_ts)
        
        now = convert_ts(now_ts, config)
        year = now.strftime("%Y")
        mon = now.strftime("%m")
        day = now.strftime("%d")
        hour = now.strftime("%H")

        #Store frame image in S3
        s3_key = (s3_key_frames_root + '{}/{}/{}/{}/{}.jpg').format(year, mon, day, hour, frame_id)
        
        s3_client.put_object(
            Bucket=s3_bucket,
            Key=s3_key,
            Body=img_bytes
        )

        s3_url = f'https://{s3_bucket}.s3.us-east-1.amazonaws.com/{s3_key}'

        try:
            rekog_response = rekog_client.search_faces_by_image(
                CollectionId=collection_id,
                FaceMatchThreshold=40,
                Image={
                    'Bytes': img_bytes
                }
            )
        except Exception as e:
            #Log error and ignore frame. You might want to add that frame to a dead-letter queue.
            print(e)
            return
            

        if 'FaceMatches' in rekog_response and rekog_response['FaceMatches']:
            for faces in rekog_response['FaceMatches']:
                if faces['Face']['ExternalImageId'] not in hash:

                    res = ddb_frame_table.get_item(
                        Key={
                            'ID': int(faces['Face']['ExternalImageId'])
                        }
                    )

                    notification_txt = 'On {}...\n'.format(now.strftime('%x, %-I:%M %p %Z'))

                    notification_txt += '- "{}" was detected. {}. Click on {} to view the image'.format(
                        res['Item']['Name'], res['Item']['Message'], s3_url)

                    

                    if label_watch_sns_topic_arn:
                        resp = sns_client.publish(
                            TopicArn=label_watch_sns_topic_arn,
                            Message=notification_txt,
                            Subject='Felon detected'
                        )

                    if resp.get("MessageId", ""):
                        print("Successfully published alert message to SNS.")
                    hash.add(faces['Face']['ExternalImageId'])
        
            #Persist frame data in dynamodb

            item = {
                'frame_id': frame_id,
                'processed_timestamp' : processed_timestamp,
                'approx_capture_timestamp' : approx_capture_timestamp,
                'processed_year_month' : year + mon, #To be used as a Hash Key for DynamoDB GSI
                's3_bucket' : s3_bucket,
                's3_key' : s3_key
            }

            ddb_table.put_item(Item=item)

    print('Successfully processed {} records.'.format(len(event['Records'])))
    return

def handler(event, context):
    return process_image(event, context)