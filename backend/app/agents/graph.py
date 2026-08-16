from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import END, START, StateGraph

from app.agents.nodes import (
    hitl_checkpoint_node,
    ingest_assets_node,
    prompt_engine_node,
    quality_checker_node,
    render_video_node,
    storyboard_planner_node,
)
from app.agents.state import AgentWorkflowState


def route_after_hitl(state: AgentWorkflowState) -> str:
    if state.get("status") == "rejected":
        return END
    return "quality_checker"


def build_workflow():
    workflow = StateGraph(AgentWorkflowState)
    workflow.add_node("planner", storyboard_planner_node)
    workflow.add_node("prompt_engine", prompt_engine_node)
    workflow.add_node("hitl_checkpoint", hitl_checkpoint_node)
    workflow.add_node("quality_checker", quality_checker_node)
    workflow.add_node("ingest_assets", ingest_assets_node)
    workflow.add_node("render_video", render_video_node)

    workflow.add_edge(START, "planner")
    workflow.add_edge("planner", "prompt_engine")
    workflow.add_edge("prompt_engine", "hitl_checkpoint")
    workflow.add_conditional_edges(
        "hitl_checkpoint",
        route_after_hitl,
        {"quality_checker": "quality_checker", END: END},
    )
    workflow.add_edge("quality_checker", "ingest_assets")
    workflow.add_edge("ingest_assets", "render_video")
    workflow.add_edge("render_video", END)

    return workflow.compile(checkpointer=MemorySaver())
