# Copyright 2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# Licensed under the Amazon Software License (the "License"). You may not use this file except in compliance with the License. A copy of the License is located at
#     http://aws.amazon.com/asl/
# or in the "license" file accompanying this file. This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or implied. See the License for the specific language governing permissions and limitations under the License.
import os
import shutil
import zipfile
import time
from pynt import task
import boto3
import botocore
from botocore.exceptions import ClientError
import json
from subprocess import call
import http.server
import socketserver

def write_dir_to_zip(src, zf):
    '''Write a directory tree to an open ZipFile object.'''
    abs_src = os.path.abspath(src)
    for dirname, subdirs, files in os.walk(src):
        for filename in files:
            absname = os.path.abspath(os.path.join(dirname, filename))
            arcname = absname[len(abs_src) + 1:]
            print('zipping %s as %s' % (os.path.join(dirname, filename),
                                        arcname))
            zf.write(absname, arcname)

def read_json(jsonf_path):
    '''Read a JSON file into a dict.'''
    with open(jsonf_path, 'r') as jsonf:
        json_text = jsonf.read()
        return json.loads(json_text)

def check_bucket_exists(bucketname):
    s3 = boto3.resource('s3')
    bucket = s3.Bucket(bucketname)
    exists = True
    try:
        s3.meta.client.head_bucket(Bucket=bucketname)
    except botocore.exceptions.ClientError as e:
        # If a client error is thrown, then check that it was a 404 error.
        # If it was a 404 error, then the bucket does not exist.
        error_code = int(e.response['Error']['Code'])
        if error_code == 404:
            exists = False
    return exists

def load_image_as_bytes(file_path):
    with open(file_path, 'rb') as file:
        image_bytes = file.read()
    return image_bytes

@task()
def deletecollection(*functions):

    image_blob = load_image_as_bytes('test.jpg')

    rekognition_client = boto3.client('rekognition', region_name='us-east-1')

    rekognition_collection_name = "felon_images"

    try:
        rekognition_client.delete_collection(CollectionId=rekognition_collection_name)
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceAlreadyExistsException':
            pass  # Collection already exists
        else:
            raise

@task()
def clean():
    '''Clean build directory.'''
    print('Cleaning build directory...')

    if os.path.exists('build'):
        shutil.rmtree('build')
    
    os.mkdir('build')

@task()
def packagelambda(* functions):
    '''Package lambda functions into a deployment-ready zip files.''' 
    if not os.path.exists('build'):
        os.mkdir('build')

    os.chdir("build")

    if(len(functions) == 0):
        functions = ("framefetcher", "imageprocessor")

    for function in functions:
        print('Packaging "%s" lambda function in directory' % function)
        zipf = zipfile.ZipFile("%s.zip" % function, "w", zipfile.ZIP_DEFLATED)
        
        write_dir_to_zip("../lambda/%s/" % function, zipf)
        zipf.write("../config/%s-params.json" % function, "%s-params.json" % function)

        zipf.close()

    os.chdir("..")
    
    return


@task()
def updatelambda(*functions):
    '''Directly update lambda function code in AWS (without upload to S3).'''
    lambda_client = boto3.client('lambda')

    if(len(functions) == 0):
        functions = ("framefetcher", "imageprocessor")

    for function in functions:
        with open('build/%s.zip' % (function), 'rb') as zipf:
            lambda_client.update_function_code(
                FunctionName=function,
                ZipFile=zipf.read()
            )
    return

@task()
def deploylambda(* functions, **kwargs):
    '''Upload lambda functions .zip file to S3 for download by CloudFormation stack during creation.'''
    
    cfn_params_path = kwargs.get("cfn_params_path", "config/cfn-params.json")

    if(len(functions) == 0):
        functions = ("framefetcher", "imageprocessor")

    region_name = boto3.session.Session().region_name
    s3_keys = {}

    cfn_params_dict = read_json(cfn_params_path)
    src_s3_bucket_name = cfn_params_dict["SourceS3BucketParameter"]
    s3_keys["framefetcher"] = cfn_params_dict["FrameFetcherSourceS3KeyParameter"]
    s3_keys["imageprocessor"] = cfn_params_dict["ImageProcessorSourceS3KeyParameter"]

    s3_client = boto3.client("s3")
    
    print("Checking if S3 Bucket '%s' exists..." % (src_s3_bucket_name))

    if( not check_bucket_exists(src_s3_bucket_name)):
        print("Bucket %s not found. Creating in region %s." % (src_s3_bucket_name, region_name))

        if( region_name == "us-east-1"):
            s3_client.create_bucket(
                # ACL="authenticated-read",
                Bucket=src_s3_bucket_name
            )
        else:
            s3_client.create_bucket(
                #ACL="authenticated-read",
                Bucket=src_s3_bucket_name,
                CreateBucketConfiguration={
                    "LocationConstraint": region_name
                }
            )
        s3_client.delete_public_access_block(
            Bucket=src_s3_bucket_name
        )

    for function in functions:
        
        print("Uploading function '%s' to '%s'" % (function, s3_keys[function]))
        
        with open('build/%s.zip' % (function), 'rb') as data:
            s3_client.upload_fileobj(data, src_s3_bucket_name, s3_keys[function])
    
    return

@task()
def videocapture(capturerate="30",clientdir="client"):
    '''Run the video capture client with built-in camera. Default capture rate is 1 every 30 frames.'''
    os.chdir(clientdir)
    
    call(["python", "video_cap.py", capturerate])

    os.chdir("..")

    return

@task()
def deletedata(global_params_path="config/global-params.json", cfn_params_path="config/cfn-params.json", image_processor_params_path="config/imageprocessor-params.json"):
    '''DELETE ALL collected frames and metadata in Amazon S3 and Amazon DynamoDB. Use with caution!'''
    
    cfn_params_dict = read_json(cfn_params_path)
    img_processor_params_dict = read_json(image_processor_params_path)

    frame_s3_bucket_name = cfn_params_dict["FrameS3BucketNameParameter"]
    frame_ddb_table_name = img_processor_params_dict["ddb_table"]

    proceed = input("This command will DELETE ALL DATA in S3 bucket '%s' and DynamoDB table '%s'.\nDo you wish to continue? [Y/N] " \
        % (frame_s3_bucket_name, frame_ddb_table_name))

    if(proceed.lower() != 'y'):
        print("Aborting deletion.")
        return


    print("Attempting to DELETE ALL OBJECTS in '%s' S3 bucket." % frame_s3_bucket_name)
    
    s3 = boto3.resource('s3')
    s3.Bucket(frame_s3_bucket_name).objects.delete()

    print("Attempting to DELETE ALL ITEMS in '%s' DynamoDB table." % frame_ddb_table_name)
    dynamodb = boto3.client('dynamodb')
    ddb_table = boto3.resource('dynamodb').Table(frame_ddb_table_name)

    last_eval_key = None
    keep_scanning = True
    batch_count = 0
    while keep_scanning:
        batch_count += 1

        if(keep_scanning and last_eval_key):
            response = dynamodb.scan(
                TableName=frame_ddb_table_name,
                Select='SPECIFIC_ATTRIBUTES',
                AttributesToGet=[
                    'frame_id',
                ],
                ExclusiveStartKey=last_eval_key
            )
        else:
            response = dynamodb.scan(
                TableName=frame_ddb_table_name,
                Select='SPECIFIC_ATTRIBUTES',
                AttributesToGet=[
                    'frame_id',
                ]
            )

        last_eval_key = response.get('LastEvaluatedKey', None)
        keep_scanning = True if last_eval_key else False

        with ddb_table.batch_writer() as batch:
            for item in response["Items"]:
                print("Deleting Item with 'frame_id': %s" % item['frame_id']['S'])
                batch.delete_item(
                    Key={
                        'frame_id': item['frame_id']['S']
                    }
                )
    print("Deleted %s batches of items from DynamoDB." % batch_count)

    return
