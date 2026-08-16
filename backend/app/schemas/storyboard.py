from typing import Literal, Optional

from pydantic import BaseModel, Field


class Scene(BaseModel):
    scene_id: int
    narration: str = Field(description="Voiceover narration line for the scene")
    visual_prompt: str = Field(description="Detailed image generation prompt")
    duration_seconds: int = Field(default=5, ge=3, le=12, description="Scene duration")
    caption_text: str = Field(default="", description="Short animated subtitle on screen")


class Storyboard(BaseModel):
    title: str
    target_audience: str
    aspect_ratio: str = "9:16"
    scenes: list[Scene]


class GenerateRequest(BaseModel):
    prompt: str = Field(min_length=3, description="Raw creative brief or URL")
    brand_guidelines: Optional[str] = Field(
        default=None, description="Optional brand tone / do-not-say rules"
    )
    aspect_ratio: str = Field(default="9:16", pattern=r"^\d+:\d+$")
    hitl_enabled: Optional[bool] = Field(
        default=None, description="Overrides HITL_REQUIRED for this job"
    )


class ApproveRequest(BaseModel):
    decision: Literal["approved", "rejected"]
    feedback: Optional[str] = Field(default=None, description="Edits to apply before rendering")


class QcReport(BaseModel):
    passed: bool
    issues: list[str] = []
    corrected_storyboard: Optional[Storyboard] = None


class JobOut(BaseModel):
    job_id: str
    status: str
    aspect_ratio: str
    storyboard: Optional[Storyboard] = None
    error: Optional[str] = None
    video_url: Optional[str] = None
    created_at: str
    updated_at: str
