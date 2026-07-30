module hashmap;

import integer_traits;

namespace utils
{

public struct hashmap_t<K, V>
        where K : INullable, IComparable, IHashable
        where V : INullable, IComparable
{
    public struct item_t
    {
        public K key;
        public V value;
    };

    public item_t* storage;
    public uint size;
    public uint capacity;

    public V get(const K key)
    {
        if(key.equals(K.zero()) || capacity == 0) { return V.zero(); }

        for(uint idx = key.hash();; idx++)
        {
            idx &= capacity - 1;
            item_t* item = storage + idx;

            if(item->key.equals(K.zero())) { return V.zero(); }
            else if(key.equals(item->key) && !item->value.equals(V.zero())) { return item->value; }
        }
    }

    public bool contains(K key) { return !get(key).equals(V.zero()); }
};

public struct mutable_hashmap_t<K, V>
        where K : INullable, IComparable, IHashable, IAtomicable
        where V : INullable, IComparable
{
    public hashmap_t<K, V> base;

    public V get(const K key) { return base.get(key); }
    public bool contains(const K key) { return base.contains(key); }

    [mutating]
    public void put(const K key, const V value)
    {
        if(key.equals(K.zero()) || base.capacity == 0) { return; }

        for(uint idx = key.hash();; idx++)
        {
            idx &= base.capacity - 1;
            hashmap_t<K, V>::item_t* item = base.storage + idx;
            K probed_key = item->key;

            if(!probed_key.equals(key))
            {
                // hit another valid entry, keep probing
                if(!probed_key.equals(K.zero()) && !item->value.equals(V.zero())) { continue; }

                // try to insert atomically
                InterlockedCompareExchange<K>(item->key, probed_key, key, probed_key);
                if(!probed_key.equals(K.zero()) && !probed_key.equals(key))
                {
                    // another thread just stole it
                    continue;
                }
                // atomically increase size
                InterlockedAdd<uint>(base.size, 1u);
            }
            item->value = value;
            return;
        }
    }
};

}
