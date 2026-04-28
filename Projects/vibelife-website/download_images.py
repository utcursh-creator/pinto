import requests
import json
import time
import os

API_KEY = "FPSXcb03ec72c01742f68d0aa03e917f355b"

# Load task IDs
with open("D:/tools/user/default/Kimi Agent Vibe Life/task_ids.json", "r") as f:
    task_ids = json.load(f)

output_dir = "D:/tools/user/default/Kimi Agent Vibe Life/app/public/images/howit"
os.makedirs(output_dir, exist_ok=True)

headers = {"x-freepik-api-key": API_KEY}

# Poll for completed images
for step, task_id in task_ids.items():
    print(f"\nChecking {step} (task: {task_id})")
    
    # Poll up to 10 times
    for attempt in range(10):
        url = f"https://api.freepik.com/v1/ai/text-to-image/runway/{task_id}"
        response = requests.get(url, headers=headers)
        result = response.json()
        
        print(f"  Attempt {attempt + 1}: Status {response.status_code}")
        
        if response.status_code == 200:
            data = result.get("data", result)
            status = data.get("status", "unknown")
            print(f"  Status: {status}")
            
            if status == "COMPLETED" or "images" in data or "image" in data:
                # Try to get image URL
                images = data.get("images", [])
                if not images and "image" in data:
                    images = [data["image"]]
                if not images and "url" in data:
                    images = [{"url": data["url"]}]
                if not images and "generated" in data:
                    images = data["generated"]
                    
                if images:
                    for i, img in enumerate(images):
                        img_url = img if isinstance(img, str) else img.get("url", "")
                        if img_url:
                            print(f"  Downloading: {img_url[:80]}...")
                            img_response = requests.get(img_url)
                            if img_response.status_code == 200:
                                filename = f"{step}.png"
                                filepath = os.path.join(output_dir, filename)
                                with open(filepath, "wb") as img_file:
                                    img_file.write(img_response.content)
                                print(f"  Saved: {filepath}")
                            else:
                                print(f"  Failed to download image")
                    break
                else:
                    print(f"  Full response: {json.dumps(data, indent=2)[:400]}")
            elif status in ["PENDING", "PROCESSING", "IN_QUEUE"]:
                print(f"  Waiting 3s...")
                time.sleep(3)
            else:
                print(f"  Response: {json.dumps(result, indent=2)[:300]}")
                break
        else:
            print(f"  Error: {json.dumps(result, indent=2)[:200]}")
            break

print("\n\nDone! Checking downloaded files:")
for f in os.listdir(output_dir):
    filepath = os.path.join(output_dir, f)
    size = os.path.getsize(filepath)
    print(f"  {f}: {size} bytes")
