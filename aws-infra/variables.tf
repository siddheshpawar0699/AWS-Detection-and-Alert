variable "image_processor_source_s3_key" {
    type = string
    default = "src/lambda_imageprocessor.zip"
}
variable "frame_fetcher_source_s3_key" {
    type = string
    default = "src/lambda_framefetcher.zip"
}
variable "frame_fetcher_lambda_function_name" {
    type = string
    default = "framefetcher"
}
variable "image_processor_lambda_function_name" {
    type = string
    default = "imageprocessor"
}
variable "frame_fetcher_api_resource_path_part" {
    type = string
    default = "enrichedframe"
}
variable "kinesis_stream_name" {
    type = string
    default = "FrameStream"
}
variable "ddb_table_name" {
    type = string
    default = "EnrichedFrame"
}
variable "ddb_global_secondary_index_name" {
    type = string
    default = "processed_year_month-processed_timestamp-index"
}
variable "api_gateway_rest_api_name" {
    type = string
    default = "VidAnalyzerRestApi"
}
variable "api_gateway_stage_name" {
    type = string
    default = "development"
}
variable "api_gateway_usage_plan_name" {
    type = string
    default = "development-plan"
}