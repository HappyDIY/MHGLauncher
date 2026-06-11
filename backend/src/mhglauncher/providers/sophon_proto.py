from dataclasses import dataclass

import betterproto


@dataclass(eq=False, repr=False)
class AssetChunk(betterproto.Message):
    chunk_name: str = betterproto.string_field(1)
    chunk_decompressed_hash_md5: str = betterproto.string_field(2)
    chunk_on_file_offset: int = betterproto.int64_field(3)
    chunk_size: int = betterproto.int64_field(4)
    chunk_size_decompressed: int = betterproto.int64_field(5)


@dataclass(eq=False, repr=False)
class AssetProperty(betterproto.Message):
    asset_name: str = betterproto.string_field(1)
    asset_chunks: list[AssetChunk] = betterproto.message_field(2)
    asset_type: int = betterproto.int32_field(3)
    asset_size: int = betterproto.int64_field(4)
    asset_hash_md5: str = betterproto.string_field(5)


@dataclass(eq=False, repr=False)
class SophonManifest(betterproto.Message):
    assets: list[AssetProperty] = betterproto.message_field(1)
