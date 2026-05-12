"""
Shared LLM factory for all agent nodes.
Uses DefaultAzureCredential (az login) — no API key needed.
"""
from __future__ import annotations
import os
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from langchain_openai import AzureChatOpenAI

load_dotenv()

_PROJECT_ENDPOINT = os.getenv("PROJECT_ENDPOINT", "")
_AZURE_ENDPOINT = _PROJECT_ENDPOINT.split("/api/projects")[0]
_API_VERSION = "2024-10-01-preview"

def _token_provider():
    return get_bearer_token_provider(
        DefaultAzureCredential(),
        "https://cognitiveservices.azure.com/.default",
    )

def get_llm(deployment: str = "gpt-4o", temperature: float = 0.0) -> AzureChatOpenAI:
    """
    Return an AzureChatOpenAI instance for the given deployment.

    Recommended role mapping (configure deployments on your own Azure
    AI Foundry resource and reference them by name):
      gpt-4o       — orchestrator, sql_writer, assembler  (strong reasoning + code)
      gpt-4o-mini  — schema_agent, clinical_agent         (fast, cheap lookups)
    """
    return AzureChatOpenAI(
        azure_endpoint=_AZURE_ENDPOINT,
        azure_deployment=deployment,
        api_version=_API_VERSION,
        azure_ad_token_provider=_token_provider(),
        temperature=temperature,
    )

# Pre-built singletons used by nodes
LLM_STRONG = get_llm("gpt-4o",      temperature=0.0)   # orchestrator, sql_writer, assembler
LLM_FAST   = get_llm("gpt-4o-mini", temperature=0.0)   # schema_agent, clinical_agent
