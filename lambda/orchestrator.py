import json
import os
import boto3

s3 = boto3.client("s3")

FIRMWARE_BUCKET = os.environ.get("FIRMWARE_BUCKET", "unknown-bucket")

VERSION_MAP = {
    "v5.6.14": {
        "next_version": "v5.6.30",
        "protocol": "TURN"
    },
    "v5.6.30": {
        "next_version": "v6.15.008",
        "protocol": "MQTT"
    }
}

FIRMWARE_FILES = {
    "v5.6.14": "v5.06.014-TURN.puf",
    "v5.6.30": "v5.06.030-TURN.puf",
    "v6.15.008": "v6.15.008-MQTT.puf"
}


def lambda_handler(event, context):
    if "body" in event:
        try:
            payload = json.loads(event["body"]) if isinstance(event["body"], str) else event["body"]
        except Exception:
            payload = {}
    else:
        payload = event

    current_version = payload.get("version")
    device_id = payload.get("device_id", "unknown-device")

    upgrade_info = VERSION_MAP.get(current_version)

    if not upgrade_info:
        return {
            "statusCode": 400,
            "body": json.dumps({
                "message": "No upgrade path found",
                "device_id": device_id,
                "current_version": current_version
            })
        }

    next_version = upgrade_info["next_version"]
    protocol = upgrade_info["protocol"]

    filename = FIRMWARE_FILES.get(next_version)

    if not filename:
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": "Firmware file mapping not found"
            })
        }

    try:
        download_url = s3.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": FIRMWARE_BUCKET,
                "Key": filename
            },
            ExpiresIn=3600
        )

        return {
            "statusCode": 200,
            "body": json.dumps({
                "device_id": device_id,
                "current_version": current_version,
                "next_version": next_version,
                "protocol": protocol,
                "firmware_file": filename,
                "download_url": download_url,
                "notes": "Presigned URL generated successfully for next firmware step."
            })
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": str(e)
            })
        }