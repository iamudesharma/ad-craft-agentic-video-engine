from typing import Any, Optional, TypedDict


class AgentWorkflowState(TypedDict, total=False):
    job_id: str
    user_prompt: str
    brand_guidelines: Optional[str]
    aspect_ratio: str
    hitl_enabled: bool
    storyboard: Optional[dict[str, Any]]
    qc_report: Optional[dict[str, Any]]
    render_items: list[dict[str, Any]]
    image_paths: list[str]
    audio_paths: list[str]
    scene_videos: list[str]
    final_video_path: Optional[str]
    status: str
    error: Optional[str]
    approval: Optional[dict[str, Any]]
    media_dir: str
