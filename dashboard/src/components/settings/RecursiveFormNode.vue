<template>
  <div class="space-y-4">
    <template v-if="Array.isArray(node)">
      <div v-for="(item, index) in node" :key="index" class="p-4 bg-gray-950 border border-gray-800 rounded-lg mb-4">
        <div class="flex justify-between items-center mb-4 border-b border-gray-800 pb-2">
          <span class="text-xs font-black text-gray-500 uppercase tracking-widest">Item {{ index + 1 }} {{ item.key ? `(${item.key})` : '' }}</span>
        </div>
        <RecursiveFormNode
          v-if="typeof item === 'object' && item !== null"
          :node="item"
          @update="val => handleArrayUpdate(index, val)"
        />
        <div v-else class="flex items-center gap-4">
          <input type="text" :value="item" @input="e => handleArrayUpdate(index, e.target.value)" class="flex-1 bg-gray-900 border border-gray-700 rounded p-2 text-sm text-gray-200" />
        </div>
      </div>
    </template>

    <template v-else-if="typeof node === 'object' && node !== null">
      <div v-for="(val, key) in node" :key="key" class="border-b border-gray-800/50 pb-4 last:border-0">
        <div class="flex flex-col md:flex-row md:items-start justify-between gap-4 mt-2">

          <div class="md:w-1/3 pt-1 text-sm font-semibold text-gray-300 capitalize">
            {{ String(key).replace(/_/g, ' ') }}
          </div>

          <div class="md:w-2/3">
            <template v-if="typeof val === 'boolean'">
              <!-- Boolean Toggle -->
              <div class="relative inline-block w-12 align-middle select-none">
                <input
                  type="checkbox"
                  :checked="val"
                  @change="e => handleObjectUpdate(key, e.target.checked)"
                  class="toggle-checkbox absolute block w-6 h-6 rounded-full bg-white border-4 appearance-none cursor-pointer transition-transform duration-200 ease-in-out"
                  :class="val ? 'translate-x-6 border-cyan-500' : 'translate-x-0 border-gray-600'"
                />
                <label
                  class="toggle-label block overflow-hidden h-6 rounded-full cursor-pointer transition-colors duration-200 ease-in-out"
                  :class="val ? 'bg-cyan-600' : 'bg-gray-800 border box-content border-gray-600'"
                  @click="handleObjectUpdate(key, !val)"
                ></label>
              </div>
            </template>

            <template v-else-if="typeof val === 'number'">
              <input
                type="number"
                :value="val"
                @input="e => handleObjectUpdate(key, Number(e.target.value))"
                class="w-full bg-gray-950 border border-gray-700 text-gray-200 text-sm rounded focus:ring-1 focus:ring-cyan-500 outline-none block p-2 object-number"
              />
            </template>

            <template v-else-if="typeof val === 'string'">
              <input
                type="text"
                :value="val"
                @input="e => handleObjectUpdate(key, e.target.value)"
                class="w-full bg-gray-950 border border-gray-700 text-gray-200 text-sm rounded focus:ring-1 focus:ring-cyan-500 outline-none block p-2"
              />
            </template>

            <template v-else-if="typeof val === 'object' && val !== null">
              <div class="pl-4 border-l-2 border-gray-800 mt-2">
                <RecursiveFormNode :node="val" @update="newVal => handleObjectUpdate(key, newVal)" />
              </div>
            </template>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  node: {
    type: [Object, Array, String, Number, Boolean],
    required: true
  },
  nodeKey: String
})

const emit = defineEmits(['update'])

const handleArrayUpdate = (index, newValue) => {
  const newArray = [...props.node]
  newArray[index] = newValue
  emit('update', newArray)
}

const handleObjectUpdate = (key, newValue) => {
  const newObj = { ...props.node }
  newObj[key] = newValue
  emit('update', newObj)
}
</script>

<style scoped>
.toggle-checkbox:checked {
  right: 0;
  border-color: #06b6d4;
}
.toggle-checkbox:checked + .toggle-label {
  background-color: #0891b2;
}
.object-number {
  max-width: 150px;
}
</style>
