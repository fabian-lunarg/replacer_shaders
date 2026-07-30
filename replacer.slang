module replacer;

import hash;
import hashmap;
import integer_traits;

// ---- shader_group_handle_t ----
static const uint k_handle_dwords = 8;

struct shader_group_handle_t
{
    uint data[k_handle_dwords];
};

extension shader_group_handle_t : utils::INullable, IComparable, utils::IHashable
{
    static shader_group_handle_t zero()
    {
        shader_group_handle_t h = {};
        return h;
    }

    bool equals(shader_group_handle_t other)
    {
        for (uint i = 0; i < k_handle_dwords; ++i)
        {
            if (data[i] != other.data[i])
            {
                return false;
            }
        }
        return true;
    }

    bool lessThan(shader_group_handle_t other)
    {
        for (uint i = 0; i < k_handle_dwords; ++i)
        {
            if (data[i] < other.data[i])
            {
                return true;
            }
            if (data[i] > other.data[i])
            {
                return false;
            }
        }
        return false;
    }

    bool lessThanOrEquals(shader_group_handle_t other)
    {
        for (uint i = 0; i < k_handle_dwords; ++i)
        {
            if (data[i] < other.data[i])
            {
                return true;
            }
            if (data[i] > other.data[i])
            {
                return false;
            }
        }
        return true;
    }

    uint hash()
    {
        uint result = 0;
        for (uint i = 0; i < k_handle_dwords; ++i)
        {
            result = utils::xxhash32(data[i], result);
        }
        return result;
    }
}

// ---- sorted_array_t: device address range map (binary search) ----
struct storage_item_t
{
    uint64_t key;
    uint64_t value;
    uint64_t size;
};

struct sorted_array_t
{
    storage_item_t *storage;
    uint num_items;
    uint _pad;
};

uint64_t map_address(sorted_array_t array, uint64_t capture_address)
{
    if (array.num_items == 0)
    {
        return uint64_t(0);
    }
    int low = 0, high = array.num_items - 1;
    while (low <= high)
    {
        int mid = low + (high - low) / 2;
        storage_item_t entry = array.storage[mid];
        uint64_t end = entry.key + max(entry.size, uint64_t(1));
        if (capture_address >= entry.key && capture_address < end)
        {
            return entry.value + (capture_address - entry.key);
        }
        else if (capture_address < entry.key)
        {
            high = mid - 1;
        }
        else
        {
            low = mid + 1;
        }
    }
    return uint64_t(0);
}

// ---- replacer_bda: remap buffer device addresses via binary search + blacklist ----
struct replacer_params_bda_t
{
    sorted_array_t device_address_array;
    utils::mutable_hashmap_t<uint64_t, uint64_t> *address_blacklist;
    uint64_t **input_handles;
    uint64_t **output_handles;
    uint num_handles;
};

[shader("compute")]
[numthreads(64, 1, 1)]
void replacer_bda(uint3 dispatch_id: SV_DispatchThreadID, uniform replacer_params_bda_t pc_bda)
{
    uint gid = dispatch_id.x;
    if (gid >= pc_bda.num_handles)
    {
        return;
    }

    uint64_t *handle_ptr = pc_bda.input_handles[gid];
    uint64_t input_address = *handle_ptr;

    // skip if already remapped and cached in the blacklist
    if (pc_bda.address_blacklist->get((uint64_t)handle_ptr) != input_address)
    {
        uint64_t result = map_address(pc_bda.device_address_array, input_address);
        pc_bda.address_blacklist->put((uint64_t)handle_ptr, result);
        *pc_bda.output_handles[gid] = result != uint64_t(0) ? result : input_address;
    }
}

// ---- replacer_rehash: migrate entries from old hashmap into a larger new one ----
struct rehash_params_t
{
    utils::hashmap_t<uint64_t, uint64_t> *hashmap_old;
    utils::mutable_hashmap_t<uint64_t, uint64_t> *hashmap_new;
};

[shader("compute")]
[numthreads(64, 1, 1)]
void replacer_rehash(uint3 dispatch_id: SV_DispatchThreadID, uniform rehash_params_t pc_rehash)
{
    uint gid = dispatch_id.x;
    if (gid >= pc_rehash.hashmap_old->capacity)
    {
        return;
    }

    utils::hashmap_t<uint64_t, uint64_t>::item_t item = pc_rehash.hashmap_old->storage[gid];
    pc_rehash.hashmap_new->put(item.key, item.value);
}

// ---- replacer_sbt: remap shader group handles in a shader binding table ----
struct replacer_params_sbt_t
{
    utils::hashmap_t<shader_group_handle_t, shader_group_handle_t> shader_group_handle_map;
    shader_group_handle_t **input_handles;
    shader_group_handle_t **output_handles;
    uint num_handles;
};

[shader("compute")]
[numthreads(64, 1, 1)]
void replacer_sbt(uint3 dispatch_id: SV_DispatchThreadID, uniform replacer_params_sbt_t pc_sbt)
{
    uint gid = dispatch_id.x;
    if (gid >= pc_sbt.num_handles)
    {
        return;
    }

    shader_group_handle_t input_handle = *pc_sbt.input_handles[gid];
    shader_group_handle_t result = pc_sbt.shader_group_handle_map.get(input_handle);
    *pc_sbt.output_handles[gid] = result.equals(shader_group_handle_t.zero()) ? input_handle : result;
}
