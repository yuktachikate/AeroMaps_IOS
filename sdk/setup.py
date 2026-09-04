from setuptools import setup, find_packages

setup(
    name="prompt_tree",
    version="0.1.0",
    packages=find_packages(),
    py_modules=["prompt_tree"],
    install_requires=[
        "requests",
    ],
    description="A lightweight SDK for tracing GenAI prompt execution trees.",
    author="GenAI Team",
    python_requires=">=3.7",
)
