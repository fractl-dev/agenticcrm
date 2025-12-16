module agenticcrm.core

{agentlang.ai/LLM {
    name "llm01",
    service "openai",
    config
    {"model": "gpt-4o"}
}}

@public agent emailExtractorAgent {
  llm "llm01",
  role "You are an AI responsible for extracting information from email."
  instruction "You "
}

@public agent emailAgent {
  llm "llm01",
  role "You are an app responsible for creating or updating hubspot contact based on email received."
  instruction "You received an email containing information about a hubspot contact. Use it to create or update the Hubspot contact. Parse the email body properly to find out name, company details, discussion happened, etc. Also include other fields if available. Additionally, summarize the email and put it into notes or comments fields if present."
  tools [hubspot/Contact]
}

workflow @after create:gmail/Email {
    this.body @as emailBody
    this.sender @as emailSender
    this.subject @as subject
    this.thread_id @as thread_id
    console.log("Email arrived:", emailBody)

    if (emailSender <> "admin@fractl.io") {
        {emailAgent {message emailBody}} @as result
        if (result.result == "success") {
        {gmail/Email
            {sender "admin@fractl.io", recipients emailSender, subject subject,
            body "Contact created successfully", thread_id thread_id}}
        } else {
            {gmail/Email
            {sender "admin@fractl.io", recipients emailSender, subject subject,
            body "Failed to create contact", thread_id thread_id}}
        }
    }
}
