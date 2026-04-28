import requests
import json
import time
import os

API_KEY = "FPSXcb03ec72c01742f68d0aa03e917f355b"

# Load task IDs
with open("D:/tools/user/default/Kimi Agent Vibe Life/blog_task_ids.json", "r") as f:
    task_ids = json.load(f)

output_dir = "D:/tools/user/default/Kimi Agent Vibe Life/app/public/images/blog"
os.makedirs(output_dir, exist_ok=True)

def poll_and_download(step_name, task_id):
    """Poll for completion and download the image."""
    url = f"https://api.freepik.com/v1/ai/text-to-image/runway/{task_id}"
    headers = {"x-freepik-api-key": API_KEY}
    
    max_attempts = 30
    for attempt in range(max_attempts):
        try:
            response = requests.get(url, headers=headers)
            print(f"\nChecking {step_name} (task: {task_id})")
            print(f"  Attempt {attempt + 1}: Status {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                data = result.get("data", {})
                status = data.get("status", "").upper()
                
                print(f"  Status: {status}")
                
                if status == "COMPLETED":
                    # Get image URL - handle both list of strings and list of dicts
                    images = data.get("images") or data.get("generated", [])
                    if images and len(images) > 0:
                        first_image = images[0]
                        # Handle if it's a string URL directly
                        if isinstance(first_image, str):
                            image_url = first_image
                        else:
                            image_url = first_image.get("url")
                        
                        print(f"  Downloading: {image_url[:80]}...")
                        
                        # Download image
                        img_response = requests.get(image_url)
                        if img_response.status_code == 200:
                            output_path = os.path.join(output_dir, f"{step_name}.png")
                            with open(output_path, "wb") as img_file:
                                img_file.write(img_response.content)
                            print(f"  Saved: {output_path}")
                            return True
                        else:
                            print(f"  Download failed: {img_response.status_code}")
                    else:
                        print(f"  No images in response: {data}")
                    return False
                    
                elif status == "FAILED":
                    print(f"  Generation failed")
                    return False
                    
                elif status in ["PENDING", "PROCESSING", "IN_PROGRESS"]:
                    print(f"  Still processing, waiting 5s...")
                    time.sleep(5)
                else:
                    print(f"  Unknown status: {status}")
                    time.sleep(3)
            else:
                print(f"  API error: {response.text[:200]}")
                time.sleep(3)
                
        except Exception as e:
            print(f"  Error: {e}")
            time.sleep(3)
    
    print(f"  Timeout after {max_attempts} attempts")
    return False

# Process all tasks
for step_name, task_id in task_ids.items():
    poll_and_download(step_name, task_id)

print("\nDone! Checking downloaded files:")
for f in os.listdir(output_dir):
    path = os.path.join(output_dir, f)
    print(f"  {f}: {os.path.getsize(path)} bytes")
