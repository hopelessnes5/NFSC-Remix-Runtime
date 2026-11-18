#include "dxvk_pipecache.h"
#include <iomanip>
#include <sstream>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace dxvk {
  
  DxvkPipelineCache::DxvkPipelineCache(
    const Rc<vk::DeviceFn>& vkd,
    const VkPhysicalDeviceProperties& properties,
    bool persist)
  : m_vkd(vkd) {
    constexpr size_t kMaxCacheBytes = 256u * 1024u * 1024u;
    std::vector<char> data;
    if (persist) {
      std::ostringstream name;
      name << env::getExeBaseName() << ".vk-pipeline-" << std::hex
           << properties.vendorID << '-' << properties.deviceID << '-' << properties.driverVersion << '-';
      for (uint8_t byte : properties.pipelineCacheUUID)
        name << std::setw(2) << std::setfill('0') << unsigned(byte);
      name << ".cache";
      auto dir = env::getEnvVar("DXVK_STATE_CACHE_PATH");
      m_path = (dir.empty() ? std::filesystem::path(".") : std::filesystem::u8path(dir)) / name.str();
      std::ifstream file(m_path, std::ios::binary | std::ios::ate);
      if (file) {
        auto length = file.tellg();
        if (length >= std::streamoff(40 + sizeof(VkPipelineCacheHeaderVersionOne)) &&
            length <= std::streamoff(40 + kMaxCacheBytes)) {
          file.seekg(0);
          char checksum[40];
          file.read(checksum, sizeof(checksum));
          data.resize(size_t(length) - sizeof(checksum));
          file.read(data.data(), data.size());
          VkPipelineCacheHeaderVersionOne header{};
          std::memcpy(&header, data.data(), sizeof(header));
          if (!file || std::string(checksum, sizeof(checksum)) != Sha1Hash::compute(data.data(), data.size()).toString() ||
              header.headerSize < sizeof(header) || header.headerSize > data.size() ||
              header.headerVersion != VK_PIPELINE_CACHE_HEADER_VERSION_ONE ||
              header.vendorID != properties.vendorID || header.deviceID != properties.deviceID ||
              std::memcmp(header.pipelineCacheUUID, properties.pipelineCacheUUID, VK_UUID_SIZE) != 0) {
            data.clear();
            Logger::warn("Pipeline cache: ignored invalid or incompatible saved data");
          } else {
            Logger::info(str::format("Pipeline cache: loading ", data.size(), " bytes"));
          }
        }
      }
    }
    VkPipelineCacheCreateInfo info;
    info.sType            = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;
    info.pNext            = nullptr;
    info.flags            = 0;
    info.initialDataSize  = data.size();
    info.pInitialData     = data.empty() ? nullptr : data.data();
    
    VkResult result = m_vkd->vkCreatePipelineCache(m_vkd->device(), &info, nullptr, &m_handle);
    if (result != VK_SUCCESS && !data.empty()) {
      info.initialDataSize = 0;
      info.pInitialData = nullptr;
      result = m_vkd->vkCreatePipelineCache(m_vkd->device(), &info, nullptr, &m_handle);
      Logger::warn("Pipeline cache: saved data rejected, retrying with an empty cache");
    }
    if (result != VK_SUCCESS)
      throw DxvkError("DxvkPipelineCache: Failed to create cache");
  }
  
  
  DxvkPipelineCache::~DxvkPipelineCache() {
    save();
    m_vkd->vkDestroyPipelineCache(
      m_vkd->device(), m_handle, nullptr);
  }

  void DxvkPipelineCache::save() {
    try {
    std::lock_guard<std::mutex> lock(m_saveMutex);
    if (m_saveTask.valid() && m_saveTask.wait_for(std::chrono::seconds(0)) != std::future_status::ready)
      return;
    if (!m_path.empty()) {
      constexpr size_t kMaxCacheBytes = 256u * 1024u * 1024u;
      size_t size = 0;
      if (m_vkd->vkGetPipelineCacheData(m_vkd->device(), m_handle, &size, nullptr) == VK_SUCCESS &&
          size > sizeof(VkPipelineCacheHeaderVersionOne) && size <= kMaxCacheBytes) {
        std::vector<char> data(size);
        if (m_vkd->vkGetPipelineCacheData(m_vkd->device(), m_handle, &size, data.data()) == VK_SUCCESS) {
          data.resize(size);
          auto tmp = m_path;
#ifdef _WIN32
          tmp += "." + std::to_string(GetCurrentProcessId()) + "." + std::to_string(reinterpret_cast<uintptr_t>(this)) + ".tmp";
#else
          tmp += "." + std::to_string(getpid()) + "." + std::to_string(reinterpret_cast<uintptr_t>(this)) + ".tmp";
#endif
          const auto path = m_path;
          m_saveTask = std::async(std::launch::async, [data = std::move(data), tmp, path]() {
          const std::string checksum = Sha1Hash::compute(data.data(), data.size()).toString();
          std::ofstream file(tmp, std::ios::binary | std::ios::trunc);
          file.write(checksum.data(), checksum.size());
          file.write(data.data(), data.size());
          file.close();
          if (file) {
#ifdef _WIN32
            const bool saved = MoveFileExW(tmp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
            std::error_code ec;
            std::filesystem::rename(tmp, path, ec);
            const bool saved = !ec;
#endif
            if (saved)
              Logger::info(str::format("Pipeline cache: saved ", data.size(), " bytes"));
            else
              Logger::warn("Pipeline cache: could not replace cache file");
          } else {
            Logger::warn("Pipeline cache: could not write cache file");
          }
          std::error_code removeError;
          std::filesystem::remove(tmp, removeError);
          });
        }
      } else {
        Logger::info(str::format("Pipeline cache: driver returned ", size, " bytes; nothing useful to save"));
      }
    }
    } catch (...) {
      // Cache persistence is optional and must never abort device shutdown.
    }
  }
  
}
