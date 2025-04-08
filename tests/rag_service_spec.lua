local mock = require("luassert.mock")
local match = require("luassert.match")

describe("RagService", function()
  local RagService
  local Config_mock

  before_each(function()
    -- Load the module before each test
    RagService = require("avante.rag_service")

    -- Setup common mocks
    Config_mock = mock(require("avante.config"), true)
    -- Mock with both the old and new configuration options
    Config_mock.rag_service = {
      host_mount = "/home/user",
      host_mounts = {} -- Empty by default to test backward compatibility
    }
  end)

  after_each(function()
    -- Clean up after each test
    package.loaded["avante.rag_service"] = nil
    mock.revert(Config_mock)
  end)

  describe("get_host_mounts", function()
    it("should use host_mount for backward compatibility when host_mounts is empty", function()
      Config_mock.rag_service = {
        host_mount = "/home/user",
        host_mounts = {}
      }

      local mounts = RagService.get_host_mounts()
      assert.equals(1, #mounts)
      assert.equals("/home/user", mounts[1])
    end)

    it("should prioritize host_mounts when available", function()
      Config_mock.rag_service = {
        host_mount = "/home/user",
        host_mounts = { "/path1", "/path2" }
      }

      local mounts = RagService.get_host_mounts()
      assert.equals(2, #mounts)
      assert.equals("/path1", mounts[1])
      assert.equals("/path2", mounts[2])
    end)

    it("should default to HOME if neither host_mount nor host_mounts are set", function()
      Config_mock.rag_service = {}

      -- Save original os.getenv function
      local original_getenv = os.getenv
      -- Mock os.getenv
      os.getenv = function(var)
        if var == "HOME" then return "/home/testuser" end
        return original_getenv(var)
      end

      local mounts = RagService.get_host_mounts()
      assert.equals(1, #mounts)
      assert.equals("/home/testuser", mounts[1])

      -- Restore original os.getenv
      os.getenv = original_getenv
    end)
  end)

  describe("get_docker_mount_args", function()
    it("should generate correct mount args for single mount", function()
      Config_mock.rag_service = {
        host_mount = "/home/user",
        host_mounts = {}
      }

      local mount_args = RagService.get_docker_mount_args()
      assert.equals(" -v /home/user:/host1:ro", mount_args)
    end)

    it("should generate correct mount args for multiple mounts", function()
      Config_mock.rag_service = {
        host_mounts = { "/path1", "/path2", "/path3" }
      }

      local mount_args = RagService.get_docker_mount_args()
      assert.equals(" -v /path1:/host1:ro -v /path2:/host2:ro -v /path3:/host3:ro", mount_args)
    end)
  end)

  describe("URI conversion functions", function()
    it("should convert URIs between host and container formats with single mount", function()
      Config_mock.rag_service = {
        host_mount = "/home/user",
        host_mounts = {}
      }

      -- Test both directions of conversion
      local host_uri = "file:///home/user/project/file.txt"
      local container_uri = "file:///host1/project/file.txt"

      -- Host to container
      local result1 = RagService.to_container_uri(host_uri)
      assert.equals(container_uri, result1)

      -- Container to host
      local result2 = RagService.to_local_uri(container_uri)
      assert.equals(host_uri, result2)
    end)

    it("should convert URIs between host and container formats with multiple mounts", function()
      Config_mock.rag_service = {
        host_mounts = { "/home/user", "/data/code" }
      }

      -- Test first mount point
      local host_uri1 = "file:///home/user/project/file.txt"
      local container_uri1 = "file:///host1/project/file.txt"

      local result1a = RagService.to_container_uri(host_uri1)
      assert.equals(container_uri1, result1a)

      local result1b = RagService.to_local_uri(container_uri1)
      assert.equals(host_uri1, result1b)

      -- Test second mount point
      local host_uri2 = "file:///data/code/project/file.txt"
      local container_uri2 = "file:///host2/project/file.txt"

      local result2a = RagService.to_container_uri(host_uri2)
      assert.equals(container_uri2, result2a)

      local result2b = RagService.to_local_uri(container_uri2)
      assert.equals(host_uri2, result2b)
    end)

    it("should return the URI unchanged if it doesn't match any mount points", function()
      Config_mock.rag_service = {
        host_mounts = { "/home/user", "/data/code" }
      }

      local unmapped_uri = "file:///var/lib/project/file.txt"
      local result = RagService.to_container_uri(unmapped_uri)
      assert.equals(unmapped_uri, result)

      local unmapped_container_uri = "file:///host3/project/file.txt"
      local result2 = RagService.to_local_uri(unmapped_container_uri)
      assert.equals(unmapped_container_uri, result2)
    end)

    it("should return URIs unchanged for non-file schemes", function()
      Config_mock.rag_service = {
        host_mounts = { "/home/user", "/data/code" }
      }

      local http_uri = "https://example.com/file.txt"
      local result = RagService.to_container_uri(http_uri)
      assert.equals(http_uri, result)

      local result2 = RagService.to_local_uri(http_uri)
      assert.equals(http_uri, result2)
    end)
  end)
end)
