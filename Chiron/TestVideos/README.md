# Test Videos for Pose Pipeline Validation

Place short (10-30s) .mp4 test clips here. Add them to the Xcode target
so `VideoTestRunner` can load them from the app bundle.

## Required clips

| File name              | Exercise           |
|------------------------|--------------------|
| `test_squat.mp4`      | Bodyweight squat   |
| `test_deadlift.mp4`   | Deadlift           |
| `test_bench.mp4`      | Bench press        |
| `test_row.mp4`        | Barbell row        |

## Recording guidelines

- Film from the same angles the app uses (front camera, roughly 6-8 ft).
- Include 3-5 clear reps with good form.
- Keep lighting consistent and background uncluttered.
- Resolution: 720p is fine (matches app camera preset).

## Usage

Open **Settings → Developer → Video Tests**, then tap **Run All Test Videos**.
Results (latency, jitter, landmark JSON) are saved to **Documents/TestResults**.
