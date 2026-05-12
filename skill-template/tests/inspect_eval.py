# Inspect AI evaluation for agentic / multi-turn skills.
# Required for permission-tier 2+ skills. Optional for tier 1.

from inspect_ai import Task, task
from inspect_ai.dataset import Sample
from inspect_ai.scorer import model_graded_qa
from inspect_ai.solver import generate, use_tools
from inspect_ai.tool import bash


@task
def skill_eval() -> Task:
    return Task(
        dataset=[
            Sample(
                input="<user message that should trigger the skill>",
                target=(
                    "<expected agent behaviour described in plain language; "
                    "the model_graded_qa scorer judges the trace against this>"
                ),
            ),
        ],
        solver=[use_tools([bash(timeout=30)]), generate()],
        scorer=model_graded_qa(model="anthropic/claude-opus-4-7"),
    )
