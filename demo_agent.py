from prompt_tree import Tracer, trace_node
import time
import requests
import random
import json

# Initialize tracer with the new port
tracer = Tracer(session_name=f"OpenSource_Analyst_Agent", api_host="http://localhost:8081")

# Target Open Source Project
REPO_OWNER = "tiangolo"
REPO_NAME = "fastapi"
URL = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}"

@trace_node(name="OS_Analyst_Main", metadata={"narration": "Hello! I am your AI assistant. I am going to start researching this software project for you. Let's see what we can find!"})
def main_analysis(repo_name):
    print(f"🚀 Starting analysis for {repo_name}...")
    
    meta = fetch_repo_metadata(repo_name)
    features = extract_features(meta["description"])
    stats = analyze_stats(meta)
    
    # Readme
    readme_content = fetch_readme(repo_name)
    summary = summarize_readme(readme_content[:2000])
    
    # Final Report
    report = generate_report(features, stats, summary)
    return report

@trace_node(name="Tool: GitHub_API_Fetch", metadata={"narration": "First, I am connecting to GitHub. Think of this like checking the library catalog to see the basic details about a book.", "tool": "github"})
def fetch_repo_metadata(repo_name):
    print(f"📡 Fetching metadata for {repo_name}...")
    time.sleep(1.5) # Simulate API latency
    return {
        "repo": repo_name,
        "stars": 45000,
        "forks": 3200,
        "description": "FastAPI framework, high performance, easy to learn, fast to code, ready for production",
        "language": "Python"
    }

@trace_node(name="LLM: Extract_Key_Features", metadata={"narration": "Now, I am reading the project description. I am looking for the most important features, kind of like reading the back of the book cover."})
def extract_features(description):
    print(f"🧠 Extracting features...")
    time.sleep(2.0) # Simulate thinking
    return ["High Performance (fastapi)", "Easy to use", "Production ready", "Python based"]

@trace_node(name="Tool: Statistical_Analysis", metadata={"narration": "I'm running some math now. I want to see how popular this project is by looking at its star rating and activity."})
def analyze_stats(meta):
    print(f"📊 Analyzing repository statistics...")
    time.sleep(0.8)
    return {
        "popularity_score": 9.8,
        "velocity": "High",
        "community_health": "Excellent"
    }

@trace_node(name="Tool: Fetch_README", metadata={"narration": "Time to dig deeper! I am downloading the main instruction manual, called the Read Me, to understand how it works."})
def fetch_readme(repo_name):
    print(f"📖 Reading documentation...")
    time.sleep(1.2)
    return """
    # FastAPI
    FastAPI is a modern, fast (high-performance), web framework for building APIs with Python 3.6+ based on standard Python type hints.
    
    ## Key Features
    * **Fast**: Very high performance, on par with NodeJS and Go (thanks to Starlette and Pydantic).
    * **Fast to code**: Increase the speed to develop features by about 200% to 300%.
    * **Fewer bugs**: Reduce about 40% of human (developer) induced errors.
    * **Intuitive**: Great editor support. Completion everywhere. Less time debugging.
    * **Easy**: Designed to be easy to use and learn. Less time reading docs.
    * **Short**: Minimize code duplication. Multiple features from each parameter declaration. Fewer bugs.
    * **Robust**: Get production-ready code. With automatic interactive documentation.
    """

@trace_node(name="LLM: RAG_Summarization", metadata={"narration": "The manual is quite long, so I am going to read it in small chunks and summarize the important parts for you."})
def summarize_readme(content):
    chunks = [content[i:i+500] for i in range(0, len(content), 500)]
    summaries = []
    for chunk in chunks:
        summaries.append(process_chunk(chunk))
    return " ".join(summaries)

@trace_node(name="LLM: Process_Context_Chunk", metadata={"narration": "Reading a small piece of the text..."})
def process_chunk(chunk):
    time.sleep(0.5)
    return f"[Summary of chunk: {chunk[:20]}...]"

@trace_node(name="Agent: Final_Report_Generator", metadata={"narration": "I'm done! I'm putting all the pieces together into a simple final report for you to read."})
def generate_report(features, stats, summary):
    print("📑 Assembling final report...")
    time.sleep(1.0)
    return f"""
# Analysis Report: {REPO_NAME}

## 🌟 Stars: {stats.get('popularity')}
## 🔑 Key Features:
{json.dumps(features, indent=2)}

## 📝 Summary:
{summary}
    """

if __name__ == "__main__":
    print(f"--- Starting Live Demo for {REPO_OWNER}/{REPO_NAME} ---")
    
    try:
        final_report = main_analysis(f"{REPO_OWNER}/{REPO_NAME}")
        print("\n" + "="*30)
        print("Analysis Complete!")
        print("="*30)
    except Exception as e:
        print(f"Error: {e}")

    # Keep alive briefly for background threads
    time.sleep(3)
