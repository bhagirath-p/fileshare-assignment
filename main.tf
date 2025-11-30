locals {
  bucket_primary_name   = "${var.name_prefix}-files-${replace(var.primary_region, "-", "")}"
  bucket_secondary_name = "${var.name_prefix}-files-${replace(var.secondary_region, "-", "")}"
  dynamodb_table_name   = "${var.name_prefix}-metadata"
  presign_lambda_name   = "${var.name_prefix}-presign"
  api_name              = "${var.name_prefix}-api"
}

# (Just ensures files are loaded) Nothing else required here.
