"""本地图片缓存服务端点, 无需鉴权直接提供缓存图片。"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse

router = APIRouter(prefix="/images", tags=["images"])


@router.get("/gacha/{filename}")
async def serve_gacha_image(filename: str, request: Request) -> FileResponse:
    image_cache = request.app.state.image_cache
    file_path = await image_cache.get_or_download(filename)
    if file_path is None or not file_path.exists():
        raise HTTPException(status_code=404, detail="图片未缓存")
    return FileResponse(file_path, media_type="image/png")
