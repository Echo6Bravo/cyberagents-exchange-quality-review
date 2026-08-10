# Planted-defect fixture for py-untrusted-data-in-llm-prompt (dim 13, CWE-1427).
#
# The rule keys on an SDK's argument structure, so this fixture must exercise all three vocabularies:
# Anthropic `system=`, an OpenAI-style `{"role": "system", ...}` dict, and a flat completion call
# discriminated by `max_tokens=` (the AI Goat challenge-1 shape). Each must-catch line carries a
# string that appears EXACTLY ONCE so the Gate 5 mutation table can neutralise one finding at a time.
#
# No credential-shaped literals anywhere: gitleaks scans full history in CI.
#
# This prose must never spell the annotation keyword (the one that starts with "rule" and ends with
# "id") followed by a colon: semgrep reads it as a real annotation wherever it appears in the file.

import logging

import anthropic

log = logging.getLogger(__name__)
client = anthropic.Anthropic()


def get_scanned_finding_description():
    # Untrusted: authored by the owner of the scanned asset. `input()` is a stand-in for a real
    # scan feed and keeps the name defined (ruff F821) without a credential-shaped literal.
    return input()


def get_scanned_resource_name():
    return input()


finding_desc = get_scanned_finding_description()
resource_name = get_scanned_resource_name()


def triage_concat_prefix(msgs):
    # ruleid: py-untrusted-data-in-llm-prompt
    return client.messages.create(model="claude-sonnet-5", system="You are a triage bot. " + finding_desc, messages=msgs)


def triage_concat_suffix(msgs):
    # ruleid: py-untrusted-data-in-llm-prompt
    return client.messages.create(model="claude-sonnet-5", system=finding_desc + " -- follow the above.", messages=msgs)


def triage_fstring(msgs):
    # ruleid: py-untrusted-data-in-llm-prompt
    return client.messages.create(model="claude-sonnet-5", system=f"Triage rules. Context: {resource_name}", messages=msgs)


def openai_system_concat(question):
    # ruleid: py-untrusted-data-in-llm-prompt
    return [{"role": "system", "content": "Answer safely. " + question}]


def openai_system_fstring(question):
    # ruleid: py-untrusted-data-in-llm-prompt
    return [{"role": "system", "content": f"Answer safely. User asks: {question}"}]


def completion_concat_positional(llm, instruction, question):
    # ruleid: py-untrusted-data-in-llm-prompt
    return llm("Instruction: " + instruction + " Question: " + question + " Answer:", max_tokens=1000, temperature=0.9)


def completion_concat_suffix(llm, question):
    # ruleid: py-untrusted-data-in-llm-prompt
    return llm(question + " -- answer the question above.", max_tokens=512)


def completion_fstring_positional(llm, question):
    # ruleid: py-untrusted-data-in-llm-prompt
    return llm(f"Instruction: be helpful. Question: {question} Answer:", max_tokens=256)


def completion_prompt_kwarg_concat(engine, doc_text):
    # ruleid: py-untrusted-data-in-llm-prompt
    return engine(prompt="Summarise the following. " + doc_text, max_tokens=400)


def completion_prompt_kwarg_fstring(engine, doc_text):
    # ruleid: py-untrusted-data-in-llm-prompt
    return engine(prompt=f"Summarise the following: {doc_text}", max_tokens=400)


# ---- must-NOT-catch: correct forms. None of these should fire. ----

def safe_static_system(msgs):
    # ok: py-untrusted-data-in-llm-prompt
    return client.messages.create(model="claude-sonnet-5", system="You are a helpful triage assistant.", messages=msgs)


def safe_system_line_wrapped(msgs):
    # An all-literal concat split only for line length is the recommended shape, not a defect.
    # ok: py-untrusted-data-in-llm-prompt
    return client.messages.create(model="claude-sonnet-5", system="You are a triage bot. " + "Be concise.", messages=msgs)


def safe_user_turn_fix(question):
    # THE FIX: untrusted data goes in the USER turn, fenced, with a static system prompt.
    # ok: py-untrusted-data-in-llm-prompt
    return [{"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": f"<question>{question}</question>"}]


def safe_completion_static(llm):
    # ok: py-untrusted-data-in-llm-prompt
    return llm("Instruction: greet the user. Answer:", max_tokens=1000)


def safe_completion_literal_concat(llm):
    # An all-literal concat with no interpolated data -- still static, must not fire.
    # ok: py-untrusted-data-in-llm-prompt
    return llm("Instruction: " + "be helpful. Answer:", max_tokens=1000)


def safe_not_a_generation_call(question):
    # No max_tokens= => not a completion call by this rule's discriminator. A logging/string-build
    # concat must not be swept up. Documented blind spot, locked here as a tested fact.
    # ok: py-untrusted-data-in-llm-prompt
    return log.info("Instruction handler received: " + question)
