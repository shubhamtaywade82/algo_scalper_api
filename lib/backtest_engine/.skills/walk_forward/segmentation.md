# Dataset Segmentation Methods

This validation engine supports multiple walk-forward segmentation frameworks:

## Segmentation Models

1. **Rolling Window (Sliding Window)**:
   - Example: 12 months training window, 3 months testing window.
   - Once computed, slide both windows forward by 3 months.
   - Maintains a constant data size for optimization.

2. **Anchored (Expanding Training Window)**:
   - Example: Start training with 12 months, test next 3 months.
   - For the next roll, expand training to 15 months, test next 3 months.
   - Useful for capturing a larger set of market regimes as history builds.
