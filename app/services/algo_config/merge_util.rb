# frozen_string_literal: true

class AlgoConfig
  # Deep-merge used for YAML seed, legacy overrides, calibration patches, and tier presets.
  module MergeUtil
    module_function

    def deep_merge_hashes_with_arrays(base, overrides)
      merged = base.dup

      overrides.each do |key, val|
        if base[key].is_a?(Hash) && val.is_a?(Hash)
          merged[key] = deep_merge_hashes_with_arrays(base[key], val)
        elsif base[key].is_a?(Array) && val.is_a?(Array)
          merged[key] = merge_arrays(base[key], val)
        else
          merged[key] = val
        end
      end

      merged
    end

    def merge_arrays(base_arr, override_arr)
      return override_arr unless base_arr.all? { |i| i.is_a?(Hash) && i[:key] } &&
                                 override_arr.all? { |i| i.is_a?(Hash) && i[:key] }

      merged_arr = base_arr.map(&:dup)

      override_arr.each do |over_item|
        existing_idx = merged_arr.index { |b_item| b_item[:key] == over_item[:key] }
        if existing_idx
          merged_arr[existing_idx] = deep_merge_hashes_with_arrays(merged_arr[existing_idx], over_item)
        else
          merged_arr << over_item
        end
      end

      merged_arr
    end
  end
end
