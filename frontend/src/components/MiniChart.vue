<script setup lang="ts">
// 와이어프레임용 예시 차트. 실제 개발 시 차트 라이브러리로 교체
const props = defineProps<{ type: 'bar' | 'line'; data: number[]; labels?: string[]; limit?: number }>()
const max = Math.max(...props.data, props.limit ?? 0) * 1.3
const y = (v: number) => 100 - (v / max) * 100
const points = props.data.map((v, i) => `${(i / (props.data.length - 1)) * 100},${y(v)}`).join(' ')
</script>

<template>
  <div v-if="type === 'bar'" class="fill bars">
    <div v-for="(v, i) in data" :key="i" class="bar-col">
      <div class="bar-area">
        <small>{{ v }}</small>
        <div class="bar" :style="{ height: (v / max) * 100 + '%' }"></div>
      </div>
      <small>{{ labels?.[i] }}</small>
    </div>
  </div>
  <svg v-else class="fill" viewBox="0 0 100 100" preserveAspectRatio="none">
    <line v-if="limit" x1="0" x2="100" :y1="y(limit)" :y2="y(limit)" stroke="#c33" stroke-width="2" stroke-dasharray="6 4" vector-effect="non-scaling-stroke" />
    <polyline :points="points" fill="none" stroke="#333" stroke-width="3" vector-effect="non-scaling-stroke" />
  </svg>
</template>
