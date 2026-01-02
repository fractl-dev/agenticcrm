{
  "agentlang": {
    "service": {
      "port": 8080,
      "httpFileHandling": false
    },
    "store": {
      "type": "sqlite",
      "dbname": "agenticcrm.db"
    },
    "monitoring": {
      "enabled": true
    },
    "retry": [
      {
        "name": "classifyRetry",
        "attempts": 3,
        "backoff": {
          "strategy": "linear",
          "delay": 2,
          "magnitude": "seconds",
          "factor": 2
        }
      }
    ]
  },
  "gmail": {
    "gmail/GmailConfig": {
      "id": "",
      "gmailClientId": "#js getLocalEnv('GMAIL_CLIENT_ID', '')",
      "gmailClientSecret": "#js getLocalEnv('GMAIL_CLIENT_SECRET', '')",
      "gmailRefreshToken": "#js getLocalEnv('GMAIL_REFRESH_TOKEN', '')",
      "gmailPollIntervalMinutes": "#js parseInt(getLocalEnv('GMAIL_POLL_INTERVAL_MINUTES', '15'))",
      "gmailPollMinutes": "2"
    }
  },
  "hubspot": {
    "hubspot/HubSpotConfig": {
      "accessToken": "#js getLocalEnv('HUBSPOT_ACCESS_TOKEN', '')",
      "pollIntervalMinutes": "#js parseInt(getLocalEnv('HUBSPOT_POLL_INTERVAL_MINUTES', '15'))",
      "searchResultLimit": "#js parseInt(getLocalEnv('HUBSPOT_SEARCH_RESULT_LIMIT', '100'))",
      "apiTimeout": "#js parseInt(getLocalEnv('HUBSPOT_API_TIMEOUT_MS', '30000'))",
      "active": true
    }
  },
  "agentlang.ai": [
    {
      "agentlang.ai/LLM": {
        "name": "sonnet_llm",
        "service": "anthropic",
        "config": {
          "model": "claude-sonnet-4-5",
          "maxTokens": 21333,
          "enableThinking": false,
          "temperature": 0.7,
          "budgetTokens": 8192,
          "enablePromptCaching": true,
          "stream": false,
          "enableExtendedOutput": true
        }
      }
    },
    {
      "agentlang.ai/LLM": {
        "name": "old_sonnet_llm",
        "service": "anthropic",
        "config": {
          "model": "claude-haiku-4-5",
          "maxTokens": 21333,
          "enableThinking": false,
          "temperature": 0.7,
          "budgetTokens": 8192,
          "enablePromptCaching": true,
          "stream": false,
          "enableExtendedOutput": true
        }
      }
    },
    {
      "agentlang.ai/LLM": {
        "name": "crmManager_llm",
        "service": "openai",
        "config": {}
      }
    }
  ]
}