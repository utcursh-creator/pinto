import requests
import json
import time
import os

API_KEY = "FPSXcb03ec72c01742f68d0aa03e917f355b"

# Blog cover image prompts - abstract, conceptual, Dan Koe style
prompts = [
    {
        "step": "blog_01",
        "prompt": "abstract minimalist illustration, broken puzzle pieces being assembled by invisible hands, golden light rays, dark moody background, conceptual art style, premium editorial look, no text"
    },
    {
        "step": "blog_02", 
        "prompt": "abstract illustration of two silhouettes merging together, one small and one large, representing partnership and embedding, flowing golden threads connecting them, dark background, conceptual art, no text"
    },
    {
        "step": "blog_03",
        "prompt": "split abstract composition, left side chaotic tangled wires, right side elegant flowing golden streams, comparison visual, dark premium background, minimalist style, no text"
    },
    {
        "step": "blog_04",
        "prompt": "abstract time-lapse illustration of gears and cogs assembling themselves, dynamic motion blur effect, warm gold and dark tones, precision engineering aesthetic, conceptual art, no text"
    },
    {
        "step": "blog_05",
        "prompt": "abstract scales balancing bars of gold against intangible cloud-like concepts, value and pricing visualization, dark moody background, premium editorial illustration, no text"
    },
    {
        "step": "blog_06",
        "prompt": "abstract open book with glowing knowledge particles floating upward, wisdom transfer visualization, warm golden ambient light, dark background, conceptual art style, no text"
    },
    {
        "step": "blog_07",
        "prompt": "abstract futuristic visualization of neural network patterns merging with mechanical gears, AI meets automation, golden nodes and dark pathways, conceptual tech art, no text"
    }
]

# Create output directory
output_dir = "D:/tools/user/default/Kimi Agent Vibe Life/app/public/images/blog"
os.makedirs(output_dir, exist_ok=True)

# Store task IDs
task_ids = {}

# Submit all image generation tasks
print("Submitting blog image generation tasks...")
for item in prompts:
    url = "https://api.freepik.com/v1/ai/text-to-image/runway"
    payload = {
        "prompt": item["prompt"],
        "ratio": "1280:720"
    }
    headers = {
        "x-freepik-api-key": API_KEY,
        "Content-Type": "application/json"
    }
    
    try:
        response = requests.post(url, json=payload, headers=headers)
        result = response.json()
        print(f"Step {item['step']}: {response.status_code}")
        
        if response.status_code == 200 or response.status_code == 201:
            if "data" in result and isinstance(result["data"], dict) and "task_id" in result["data"]:
                task_ids[item["step"]] = result["data"]["task_id"]
                print(f"  Task ID: {result['data']['task_id']}")
            elif "id" in result:
                task_ids[item["step"]] = result["id"]
                print(f"  ID: {result['id']}")
            elif "task_id" in result:
                task_ids[item["step"]] = result["task_id"]
                print(f"  Task ID: {result['task_id']}")
            else:
                print(f"  Response: {json.dumps(result, indent=2)[:300]}")
        else:
            print(f"  Error: {json.dumps(result, indent=2)[:300]}")
            
    except Exception as e:
        print(f"Error for {item['step']}: {e}")
    
    time.sleep(0.5)

print(f"\nTask IDs collected: {len(task_ids)}")
print(json.dumps(task_ids, indent=2))

# Save task IDs for later retrieval
with open("D:/tools/user/default/Kimi Agent Vibe Life/blog_task_ids.json", "w") as f:
    json.dump(task_ids, f, indent=2)
print("\nTask IDs saved to blog_task_ids.json")
