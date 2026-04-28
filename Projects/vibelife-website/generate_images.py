import requests
import json
import time
import os

API_KEY = "FPSXcb03ec72c01742f68d0aa03e917f355b"

# Dan Koe style prompts - vintage woodcut/etching, light backgrounds, high contrast black ink, detailed cross-hatching
prompts = [
    {
        "step": "01_client_closes",
        "prompt": "vintage woodcut illustration, two businessmen shaking hands, detailed cross-hatching and line work, black ink on off-white paper, 19th century engraving style, high contrast, editorial illustration, no text, antique etching aesthetic, vast negative space on left"
    },
    {
        "step": "02_kickoff", 
        "prompt": "vintage woodcut illustration, detailed compass and map spread on desk, cross-hatching technique, black ink on cream paper, 19th century engraving style, birds eye view, adventure planning, vintage cartography aesthetic, no text, etching style"
    },
    {
        "step": "03_audit",
        "prompt": "vintage woodcut illustration, detective with magnifying glass examining intricate clockwork mechanism, detailed cross-hatching, black ink on off-white background, Victorian era engraving, investigation theme, no text, antique botanical illustration style"
    },
    {
        "step": "04_build",
        "prompt": "vintage woodcut illustration, architect hands building detailed architectural model of a tower, cross-hatching and fine line work, black ink on cream paper, 19th century engineering blueprint aesthetic, construction theme, no text, etching style"
    },
    {
        "step": "05_education",
        "prompt": "vintage woodcut illustration, open ancient book with light rays emanating, owl perched nearby, detailed cross-hatching, black ink on off-white paper, wisdom and knowledge theme, 19th century engraving, library aesthetic, no text"
    },
    {
        "step": "06_support",
        "prompt": "vintage woodcut illustration, lighthouse on rocky cliff guiding ships, detailed cross-hatching and wave patterns, black ink on cream background, 19th century maritime engraving, protection and guidance theme, no text, etching style"
    }
]

# Create output directory
output_dir = "D:/tools/user/default/Kimi Agent Vibe Life/app/public/images/howit"
os.makedirs(output_dir, exist_ok=True)

# Store task IDs
task_ids = {}

# Submit all image generation tasks
print("Submitting Dan Koe style image generation tasks...")
for item in prompts:
    url = "https://api.freepik.com/v1/ai/text-to-image/runway"
    payload = {
        "prompt": item["prompt"],
        "ratio": "1920:1080"
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
with open("D:/tools/user/default/Kimi Agent Vibe Life/task_ids.json", "w") as f:
    json.dump(task_ids, f, indent=2)
print("\nTask IDs saved to task_ids.json")
