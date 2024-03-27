# term-project-team06
term-project-team06 created by GitHub Classroom

Let's go through the steps necessary to get this prototype up and running.

## Preparing your development environment
Here’s a high-level checklist of what you need to do to setup your development environment.

1. Sign up for an AWS account if you haven't already and create an Administrator User. The steps are published [here](http://docs.aws.amazon.com/lambda/latest/dg/setting-up.html).

2. Ensure that you have Python 2.7+ and Pip on your machine. Instructions for that varies based on your operating system and OS version.

3. Create a Python [virtual environment](https://virtualenv.pypa.io/en/stable/) for the project with Virtualenv. This helps keep project’s python dependencies neatly isolated from your Operating System’s default python installation. **Once you’ve created a virtual python environment, activate it before moving on with the following steps**.

4. Use Pip to [install AWS CLI](http://docs.aws.amazon.com/cli/latest/userguide/installing.html). [Configure](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) the AWS CLI. It is recommended that the access keys you configure are associated with an IAM User who has full access to the following:
 - Amazon S3
 - Amazon DynamoDB
 - Amazon Kinesis
 - AWS Lambda
 - Amazon CloudWatch and CloudWatch Logs
 - Terraform
 - Amazon Rekognition
 - Amazon SNS
 - Amazon API Gateway
 - Creating IAM Roles

 The IAM User can be the Administrator User you created in Step 1.

 5. Make sure you choose a region where all of the above services are available. Regions us-east-1 (N. Virginia), us-west-2 (Oregon), and eu-west-1 (Ireland) fulfill this criterion. Visit [this page](https://aws.amazon.com/about-aws/global-infrastructure/regional-product-services/) to learn more about service availability in AWS regions.

6. Use Pip to install [Open CV](https://github.com/opencv/opencv) 3 python dependencies and then compile, build, and install Open CV 3 (required by Video Cap clients). You can follow [this guide](http://www.pyimagesearch.com/2016/11/28/macos-install-opencv-3-and-python-2-7/) to get Open CV 3 up and running on OS X Sierra with Python 2.7. There's [another guide](http://www.pyimagesearch.com/2016/12/05/macos-install-opencv-3-and-python-3-5/) for Open CV 3 and Python 3.5 on OS X Sierra. Other guides exist as well for Windows and Raspberry Pi.

6. Use Pip to install [Boto3](http://boto3.readthedocs.io/en/latest/). Boto is the Amazon Web Services (AWS) SDK for Python, which allows Python developers to write software that makes use of Amazon services like S3 and EC2. Boto provides an easy to use, object-oriented API as well as low-level direct access to AWS services.

7. Use Pip to install [Pynt](https://github.com/rags/pynt). Pynt enables you to write project build scripts in Python.

8. Clone this GitHub repository. Choose a directory path for your project that does not contain spaces (I'll refer to the full path to this directory as _\<path-to-project-dir\>_).

9. Use Pip to install [pytz](http://pytz.sourceforge.net/). Pytz is needed for timezone calculations. Use the following commands:

```bash
pip install pytz # Install pytz in your virtual python env

pip install pytz -t <path-to-project-dir>/lambda/imageprocessor/ # Install pytz to be packaged and deployed with the Image Processor lambda function
```

Finally, you can simply use your laptop’s built-in camera.

## Configuring the project

In this section, we list every configuration file, parameters within it, and parameter default values. The build commands detailed later extract the majority of their parameters from these configuration files. Also, the prototype's two AWS Lambda functions - Image Processor and Frame Fetcher - extract parameters at runtime from `imageprocessor-params.json` and `framefetcher-params.json` respectively.

>**NOTE: Do not remove any of the attributes already specified in these files.**



> **NOTE: You must set the value of any parameter that has the tag NO-DEFAULT** 

### config/global-params.json

Specifies “global” build configuration parameters. It is read by multiple build scripts.

```json
{
    "StackName" : "video-analyzer-stack"
}
```
Parameters:

* `StackName` - The name of the stack to be created in your AWS account.

### config/cfn-params.json
Specifies and overrides default values of Terraform parameters defined in the template (located at aws-infra/aws-infra-cfn.yaml).

```json
{
    "SourceS3BucketParameter" : "<NO-DEFAULT>",
    "ImageProcessorSourceS3KeyParameter" : "src/lambda_imageprocessor.zip",
    "FrameFetcherSourceS3KeyParameter" : "src/lambda_framefetcher.zip",

    "FrameS3BucketNameParameter" : "<NO-DEFAULT>"
}
```
Parameters:

* `SourceS3BucketParameter` - The Amazon S3 bucket to which your AWS Lambda function packages (.zip files) will be deployed. If a bucket with such a name does not exist, the `deploylambda` build command will create it for you with appropriate permissions. Terraform will access this bucket to retrieve the .zip files for Image Processor and Frame Fetcher AWS Lambda functions.

* `ImageProcessorSourceS3KeyParameter` - The Amazon S3 key under which the Image Processor function .zip file will be stored.

* `FrameFetcherSourceS3KeyParameter` - The Amazon S3 key under which the Frame Fetcher function .zip file will be stored.

* `FrameS3BucketNameParameter` - The Amazon S3 bucket that will be used for storing video frame images. **There must not be an existing S3 bucket with the same name.**


### config/imageprocessor-params.json
Specifies configuration parameters to be used at run-time by the Image Processor lambda function. This file is packaged along with the Image Processor lambda function code in a single .zip file using the `packagelambda` build script.

```json
{
	"s3_bucket" : "<NO-DEFAULT>",
	"s3_key_frames_root" : "frames/",

	"ddb_table" : "EnrichedFrame",
	"ddb_input_image_table": "swen-614",

	"timezone" : "US/Eastern"
}
```

* `s3_bucket` - The Amazon S3 bucket in which Image Processor will store captured video frame images. The value specified here _must_ match the value specified for the `FrameS3BucketNameParameter` parameter in the `cfn-params.json` file.

* `s3_key_frames_root` - The Amazon S3 key prefix that will be prepended to the keys of all stored video frame images.

* `ddb_table` - The Amazon DynamoDB table in which Image Processor will store video frame metadata.

* `ddb_input_image_table` - The Amazon DynamoDB table in which Image Processor will store input image metadata.

* `timezone` - The timezone used to report time and date in email alerts. By default, it is "US/Eastern". See this list of [country codes, names, continents, capitals, and pytz timezones](https://gist.github.com/pamelafox/986163)).

### config/framefetcher-params.json
Specifies configuration parameters to be used at run-time by the Frame Fetcher lambda function. This file is packaged along with the Frame Fetcher lambda function code in a single .zip file using the ```packagelambda``` build script.

```json
{
    "s3_pre_signed_url_expiry" : 1800,

    "ddb_table" : "EnrichedFrame",
    "ddb_gsi_name" : "processed_year_month-processed_timestamp-index",

    "fetch_horizon_hrs" : 24,
    "fetch_limit" : 3
}
```

* `s3_pre_signed_url_expiry` - Frame Fetcher returns video frame metadata. Along with the returned metadata, Frame Fetcher generates and returns a pre-signed URL for every video frame. Using a pre-signed URL, a client (such as the Web UI) can securely access the JPEG image associated with a particular frame. By default, the pre-signed URLs expire in 30 minutes.

* `ddb_table` - The Amazon DynamoDB table from which Frame Fetcher will fetch video frame metadata.

* `ddb_gsi_name` - The name of the Amazon DynamoDB Global Secondary Index that Frame Fetcher will use to query frame metadata.

* `fetch_horizon_hrs` - Frame Fetcher will exclude any video frames that were ingested prior to the point in the past represented by (time now - `fetch_horizon_hrs`).

* `fetch_limit` - The maximum number of video frame metadata items that Frame Fetcher will retrieve from Amazon DynamoDB.

## Building the prototype
Common interactions with the project have been simplified for you. Using pynt, the following tasks are automated with simple commands: 

- Packaging lambda code into .zip files and deploying them into an Amazon S3 bucket
- Running the video capture client to stream from a built-in laptop webcam.

For a list of all available tasks, enter the following command in the root directory of this project:

```bash
pynt -l
```

The output represents the list of build commands available to you.

Build commands are implemented as python scripts in the file ```build.py```. The scripts use the AWS Python SDK (Boto) under the hood. They are documented in the following section.

>Prior to using these build commands, you must configure the project. Configuration parameters are split across JSON-formatted files located under the config/ directory. Configuration parameters are described in detail in an earlier section.

## Build commands

This section describes important build commands and how to use them. If you want to use these commands right away to build the prototype, you may skip to the section titled _"Deploy and run the prototype"_.

### The `packagelambda` build command

Run this command to package the prototype's AWS Lambda functions and their dependencies (Image Processor and Frame Fetcher) into separate .zip packages (one per function). The deployment packages are created under the `build/` directory.

```bash
pynt packagelambda # Package both functions and their dependencies into zip files.
```

Currently, only Image Processor requires an external dependency, [pytz](http://pytz.sourceforge.net/). If you add features to Image Processor or Frame Fetcher that require external dependencies, you should install the dependencies using Pip by issuing the following command.

```bash
pip install <module-name> -t <path-to-project-dir>/lambda/<lambda-function-dir>
```
For example, let's say you want to perform image processing in the Image Processor Lambda function. You may decide on using the [Pillow](http://pillow.readthedocs.io/en/3.0.x/index.html) image processing library. To ensure Pillow is packaged with your Lambda function in one .zip file, issue the following command:

```bash
pip install Pillow -t <path-to-project-dir>/lambda/imageprocessor #Install Pillow dependency
```

You can find more details on installing AWS Lambda dependencies [here](http://docs.aws.amazon.com/lambda/latest/dg/lambda-python-how-to-create-deployment-package.html).

### The `deploylambda` build command

Run this command after running `packagelambda`. The ```deploylambda``` command uploads Image Processor and Frame Fetcher .zip packages to Amazon S3 for pickup by Terraform while creating the prototype's stack. This command will parse the deployment Amazon S3 bucket name and keys names from the cfn-params.json file. If the bucket does not exist, the script will create it. This bucket must be in the same AWS region as the Terraform stack, or else the stack creation will fail. Without parameters, the command will deploy the .zip packages of both Image Processor and Frame Fetcher. You can specify either “imageprocessor” or “framefetcher” as a parameter between square brackets to deploy an individual function.

Here are sample command invocations.

```bash
pynt deploylambda # Deploy both functions to Amazon S3.
```

### The `deletedata` build command

The `deletedata` command, once issued, empties the Amazon S3 bucket used to store video frame images. Next, it also deletes all items in the DynamoDB table used to store frame metadata.

Use this command to clear all previously ingested video frames and associated metadata. The command will ask for confirmation [Y/N] before proceeding with deletion.

You can issue the `deletedata` command as follows.

```bash
pynt deletedata
```

### The `videocapture` build commands

On the other hand, the videocapture command (without the trailing 'ip'), fires up a video capture client that captures frames from a camera attached to the machine on which it runs. If you run this command on your laptop, for instance, the client will attempt to access its built-in video camera. This video capture client relies on Open CV 3 to capture video from physically connected cameras. Captured frames are packaged, serialized, and sent to the Kinesis Frame Stream.

Here’s a sample invocation.

```bash
pynt videocapture # Captures frames from webcam
```

## Deploy and run the prototype
In this section, we are going use project's build commands to deploy and run the prototype in your AWS account. We’ll use the commands to create the prototype's Terraform stack, and run the Video Cap client. We will replace `<no-default>` values with our desired values wherever applicable

* Prepare your development environment, and ensure configuration parameters are set as you wish. Inside `config/cfn-params.json` file, `SourceS3BucketParameter` should be replaced with Lambda files bucket name and `FrameS3BucketNameParameter` should be replaced with Rekognition frames bucket name. Similarly inside `config/imageprocessor-params.json`, replace `s3_bucket` with Rekognition frames bucket name and for `config/global-params.json`, replace `s3_bucket` with Rekognition frames bucket name, replace `app_client_id` and `user_pool_id` with Cognito IDs. Replace the same for `global-params.json` at the root of the directory.

* On your machine, in a command line terminal change into the root directory of the project. Activate your virtual Python environment. Then, enter the following commands:

```bash
$ pynt packagelambda #First, package code & configuration files into .zip files

#Command output without errors

$ pynt deploylambda #Second, deploy your lambda code to Amazon S3

#Command output without errors
```

* Edit the `aws-infra/terraform.tfvars` file to include your own email address, your desired Lambda source files S3 bucket name and Rekognition frames S3 bucket name.

* Edit the `config/cfn-params.json` to add your desired source S3 bucket name (`SourceS3BucketParameter`) and frame S3 bucket name (`FrameS3BucketNameParameter`).

* Edit the `config/imageprocessor-params.json` to add your desired frame S3 bucket name (`s3_bucket`).

* Next, deploy your infrastructure by running the following command from within the `aws-infra` directory:

```bash
$ terraform apply
```

* A Beanstalk URL will be provided in the output, use the URL to visit the Web UI

* An email will be sent to the subscribed email address. Confirm subscription to receive alert emails from the system.

* Login to the web UI using your Cognito username and Cognito password entered earlier and upload an image which needs to be detected by the system from the incoming frames.

* Finally, run the command below to start sending frames from your webcam to Amazon Kinesis:

```bash
$ pynt videocapture
```

* If a matching face is detected in the incoming frames, an alert email is sent to the user with an link to an image showing the detected face.

## When you are done
After you are done experimenting with the prototype, perform the following steps to avoid unwanted costs.

* Terminate video capture client (press Ctrl+C in command line terminal where you got it running)
* Run ```pynt deletedata``` command to delete all data in your buckets
* Execute the ```terraform destroy``` command from within `aws-infra` directory (see docs above)
* Ensure that Amazon S3 buckets and objects within them are deleted.
