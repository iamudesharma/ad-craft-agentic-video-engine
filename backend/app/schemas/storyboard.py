from typing import Literal, Optional

from pydantic import BaseModel, Field


class BrandGuidelines(BaseModel):
    brand_name: Optional[str] = Field(default=None, description="Brand name")
    tagline: Optional[str] = Field(default=None, description="Tagline or positioning statement")
    tone_of_voice: Optional[str] = Field(default=None, description="Tone of voice for copy and narration")
    colors: Optional[list[str]] = Field(default=None, description="Brand color palette (hex codes or names)")
    typography: Optional[str] = Field(default=None, description="Font / typography style")
    visual_style: Optional[str] = Field(default=None, description="Photography, illustration or motion style")
    do_list: Optional[list[str]] = Field(default=None, description="Messaging and imagery to always use")
    dont_list: Optional[list[str]] = Field(default=None, description="Messaging and imagery to never use")
    target_audience: Optional[str] = Field(default=None, description="Who the ad speaks to")

    def is_empty(self) -> bool:
        return not any(
            value
            for value in (
                self.brand_name,
                self.tagline,
                self.tone_of_voice,
                self.colors,
                self.typography,
                self.visual_style,
                self.do_list,
                self.dont_list,
                self.target_audience,
            )
        )


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
    brand_guidelines: Optional[BrandGuidelines] = Field(
        default=None, description="Optional structured brand guidelines"
    )
    aspect_ratio: str = Field(default="9:16", pattern=r"^\d+:\d+$")
    hitl_enabled: Optional[bool] = Field(
        default=None, description="Overrides HITL_REQUIRED for this job"
    )


class ApproveRequest(BaseModel):
    decision: Literal["approved", "rejected"]
    feedback: Optional[str] = Field(default=None, description="Edits to apply before rendering")
    storyboard: Optional[Storyboard] = Field(
        default=None, description="User-edited storyboard to use instead of the generated one"
    )


class RegenerateRequest(BaseModel):
    storyboard: Storyboard = Field(description="User-edited storyboard to regenerate from")


class DuplicateRequest(BaseModel):
    mode: Literal["brief", "storyboard"]


class FavoriteRequest(BaseModel):
    favorite: bool


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
