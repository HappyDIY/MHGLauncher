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


@dataclass(eq=False, repr=False)
class PatchInfo(betterproto.Message):
    id: str = betterproto.string_field(1)
    patch_file_size: int = betterproto.int64_field(4)
    patch_start_offset: int = betterproto.int64_field(6)
    patch_length: int = betterproto.int64_field(7)
    original_file_name: str = betterproto.string_field(8)


@dataclass(eq=False, repr=False)
class PatchesEntry(betterproto.Message):
    key: str = betterproto.string_field(1)
    patch_info: PatchInfo = betterproto.message_field(2)


@dataclass(eq=False, repr=False)
class PatchFileData(betterproto.Message):
    file_name: str = betterproto.string_field(1)
    file_size: int = betterproto.int64_field(2)
    file_hash: str = betterproto.string_field(3)
    patches_entries: list[PatchesEntry] = betterproto.message_field(4)


@dataclass(eq=False, repr=False)
class FileInfo(betterproto.Message):
    name: str = betterproto.string_field(1)


@dataclass(eq=False, repr=False)
class DeleteFiles(betterproto.Message):
    infos: list[FileInfo] = betterproto.message_field(1)


@dataclass(eq=False, repr=False)
class DeleteFilesEntry(betterproto.Message):
    key: str = betterproto.string_field(1)
    delete_files: DeleteFiles = betterproto.message_field(2)


@dataclass(eq=False, repr=False)
class PatchManifest(betterproto.Message):
    file_datas: list[PatchFileData] = betterproto.message_field(1)
    delete_files_entries: list[DeleteFilesEntry] = betterproto.message_field(2)
