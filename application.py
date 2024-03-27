from flask import Flask, render_template, request, redirect, url_for, session
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from flask_wtf import FlaskForm
from wtforms import StringField, FileField, TextAreaField
from wtforms.validators import InputRequired
import boto3
from botocore.exceptions import NoCredentialsError, ClientError
import uuid
from uuid import uuid4
import time
from io import BytesIO
import re
import base64
# import config 
import subprocess
import json
import os



# Use Terraform outputs
s3_client = boto3.client('s3', region_name="us-east-1")
application = Flask(__name__)
application.config['SECRET_KEY'] = 'your_secret_key'  # Change this to a secure secret key

config_file_path = "global-params.json"
config = None

with open(config_file_path, 'r') as conf_file:
    conf_json = conf_file.read()
    config = json.loads(conf_json)

client = boto3.client('cognito-idp', region_name="us-east-1")

# Configure DynamoDB
dynamodb = boto3.resource('dynamodb', region_name="us-east-1")
table_name = config['ddb_input_image_table']

# Define the S3 bucket name
s3_bucket_name = config['s3_bucket']

# Configure Flask-Login
login_manager = LoginManager()
login_manager.login_view = 'login'
login_manager.init_app(application)

# Configure Amazon Rekognition
rekognition_client = boto3.client('rekognition', region_name="us-east-1")

rekognition_collection_name = config['rekognition_col_name']

app_client_id = os.environ.get("APP_CLIENT_ID")
user_pool_id = os.environ.get("USER_POOL_ID")


class SubmitForm(FlaskForm):
    name = StringField('Name', validators=[InputRequired()])
    image = FileField('Image', validators=[InputRequired()])
    message = TextAreaField('Message', validators=[InputRequired()])

class CompareForm(FlaskForm):
    image_to_compare = FileField('Image to Compare', validators=[InputRequired()])

class User(UserMixin):
    pass

@login_manager.user_loader
def user_loader(email):
    user = User()
    user.id = email
    return user

# Create Rekognition Face Collection if it doesn't exist
def create_rekognition_collection(collection_id):
    try:
        rekognition_client.create_collection(CollectionId=collection_id)
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceAlreadyExistsException':
            pass  # Collection already exists
        else:
            raise

create_rekognition_collection(rekognition_collection_name)


@application.route('/')
def home():
    return render_template('home.html')

@application.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        email = request.form['email']
        password = request.form['password']

        try:
            response = client.sign_up(
                ClientId=app_client_id,
                Username=email,
                Password=password,
                UserAttributes=[
                    {
                        'Name': 'email',
                        'Value': email
                    },
                ]
            )

            session['registered_email'] = email  # Store the registered email in a session variable

            return redirect(url_for('login'))
        except client.exceptions.UsernameExistsException:
            return "Email already exists. Please log in."
        except NoCredentialsError:
            return "AWS credentials not found."

    return render_template('register.html')

@application.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        email = request.form['email']
        password = request.form['password']

        try:
            auth_response = client.admin_initiate_auth(
                UserPoolId=user_pool_id,
                ClientId=app_client_id,
                AuthFlow='ADMIN_NO_SRP_AUTH',
                AuthParameters={
                    'USERNAME': email,
                    'PASSWORD': password
                }
            )

            user = User()
            user.id = email
            login_user(user)

            return redirect(url_for('submit'))
        except client.exceptions.UserNotConfirmedException:
            return "Email not confirmed. Please check your email."
        except client.exceptions.NotAuthorizedException:
            return "Incorrect username or password."
        except NoCredentialsError:
            return "AWS credentials not found."

    return render_template('login.html')

@application.route('/submit', methods=['GET', 'POST'])
@login_required
def submit():
    form = SubmitForm()

    if form.validate_on_submit():
        name = form.name.data
        message = form.message.data
        image = form.image.data

        if 'cameraImage' in request.form:
            # Handle the camera image data
            image_data_url = request.form['cameraImage']
            image_data = re.sub('^data:image/.+;base64,', '', image_data_url)
            image = BytesIO(base64.b64decode(image_data))
            image_filename = f"{str(uuid4())}.png"
        else:
            # Handle the uploaded image
            image = form.image.data
            image_filename = f"{str(uuid4())}.{image.filename.split('.')[-1]}"

        try:
            # Save image to S3
            unique_id = int(time.time())
            image_filename = f"{str(uuid4())}.{image.filename.split('.')[-1]}"
            image_key = f"{image_filename}"
            s3_client.upload_fileobj(image, s3_bucket_name, image_key)
            image_url = f"https://{s3_bucket_name}.s3.amazonaws.com/{image_key}"

            # Save data to DynamoDB
            table = dynamodb.Table(table_name)
            table.put_item(
                Item={
                    'ID': unique_id,
                    'Name': name,
                    'Message': message,
                    'ImageURL': image_url,
                }
            )

            # Index faces in the Rekognition Face Collection
            response = rekognition_client.index_faces(
                CollectionId=rekognition_collection_name,
                Image={
                    'S3Object': {
                        'Bucket': s3_bucket_name,
                        'Name': image_key,
                    },
                },
                ExternalImageId=str(unique_id),
                MaxFaces=1,
                DetectionAttributes=['ALL'],
            )

            return redirect(url_for('home'))
        except Exception as e:
            print(e)
            return render_template('submit.html', form=form, error=f"Error during submission: {str(e)}")

    return render_template('submit.html', form=form)

@application.route('/compare', methods=['GET', 'POST'])
@login_required
def compare():
    form = CompareForm()

    if form.validate_on_submit():
        image_to_compare = form.image_to_compare.data

        try:
            # Save image to S3
            unique_id = int(time.time())
            image_filename = f"{str(uuid4())}.{image_to_compare.filename.split('.')[-1]}"
            image_key = f"{image_filename}"
            s3_client.upload_fileobj(image_to_compare, s3_bucket_name, image_key)

            # Search for faces in the Rekognition collection
            response = rekognition_client.search_faces_by_image(
                CollectionId=rekognition_collection_name,
                Image={
                    'S3Object': {
                        'Bucket': s3_bucket_name,
                        'Name': image_key,
                    },
                },
            )

            # Process the response
            if 'FaceMatches' in response and response['FaceMatches']:
                best_match = max(response['FaceMatches'], key=lambda match: match['Similarity'])
                similarity = best_match['Similarity']
                face_id = best_match['Face']['FaceId']
                return render_template('result.html', match=True, similarity=similarity, face_id=face_id)
            else:
                return render_template('result.html', match=False)

        except ClientError as e:
           
            return render_template('result.html', error=f"Error during face comparison: {str(e)}")

    return render_template('compare.html', form=form)   



@application.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))


if __name__ == '__main__':
    application.run(host='0.0.0.0',port=8000,debug=True)
