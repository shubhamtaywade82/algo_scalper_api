import { createRouter, createWebHistory } from 'vue-router'
import Dashboard from '../views/Dashboard.vue'
import Strategies from '../views/Strategies.vue'
import Signals from '../views/Signals.vue'
import Analysis from '../views/Analysis.vue'

const routes = [
  {
    path: '/',
    name: 'Dashboard',
    component: Dashboard
  },
  {
    path: '/strategies',
    name: 'Strategies',
    component: Strategies
  },
  {
    path: '/signals',
    name: 'Signals',
    component: Signals
  },
  {
    path: '/analysis',
    name: 'Analysis',
    component: Analysis
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

export default router
