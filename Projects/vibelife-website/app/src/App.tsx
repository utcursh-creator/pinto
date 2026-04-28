import { lazy, Suspense } from 'react';
import { BrowserRouter as Router, Routes, Route, useLocation } from 'react-router-dom';
import { AnimatePresence } from 'framer-motion';
import { SmoothScroll } from '@/components/layout/SmoothScroll';
import { GSAPProvider } from '@/components/providers/GSAPProvider';
import { PageTransition } from '@/components/layout/PageTransition';

const HomePage = lazy(() => import('@/pages/HomePage').then(m => ({ default: m.HomePage })));
const HowItWorksPage = lazy(() => import('@/pages/HowItWorksPage').then(m => ({ default: m.HowItWorksPage })));
const WhatWeBuildPage = lazy(() => import('@/pages/WhatWeBuildPage').then(m => ({ default: m.WhatWeBuildPage })));
const ResourcesPage = lazy(() => import('@/pages/ResourcesPage').then(m => ({ default: m.ResourcesPage })));

function AnimatedRoutes() {
  const location = useLocation();

  return (
    <AnimatePresence mode="wait">
      <Suspense fallback={<div className="min-h-screen bg-void" />} key={location.pathname}>
        <Routes location={location}>
          <Route path="/" element={<PageTransition><HomePage /></PageTransition>} />
          <Route path="/how-it-works" element={<PageTransition><HowItWorksPage /></PageTransition>} />
          <Route path="/work" element={<PageTransition><WhatWeBuildPage /></PageTransition>} />
          <Route path="/resources" element={<PageTransition><ResourcesPage /></PageTransition>} />
        </Routes>
      </Suspense>
    </AnimatePresence>
  );
}

function App() {
  return (
    <Router>
      <GSAPProvider>
        <SmoothScroll>
          <AnimatedRoutes />
        </SmoothScroll>
      </GSAPProvider>
    </Router>
  );
}

export default App;
