// Reactions besides the 1–3 star rating. Names are shared with the iOS app.
export const KINDS = ['creative', 'funny', 'wild']; // ✍️ 😂 🫪
export const MAX_STARS = 3;

// Points behind the weekly awards. They are never shown: "friend of the week"
// is whoever has the most, "most active" only looks at the activity part.
export const POINTS = {
  star: 1, // each star your photos received
  reaction: 1, // each ✍️ / 😂 / 🫪 your photos received
  post: 2, // each photo you posted…
  postCap: 14, // …counted up to this many per week, so spamming doesn't win
  given: 1, // each rating or reaction you gave to friends' photos
};

/**
 * @param {{ members: {id: string, name: string}[],
 *           photos: {id: string, authorId: string, createdAt: number, caption?: string|null, file: string}[],
 *           reactions: {photoId: string, userId: string, kind: string}[],
 *           stars: {photoId: string, userId: string, value: number}[] }} input
 */
export function computeStandings({ members, photos, reactions, stars = [] }) {
  const stats = new Map(
    members.map((m) => [
      m.id,
      { userId: m.id, name: m.name, points: 0, activity: 0, posts: 0, given: 0, stars: 0, creative: 0, funny: 0, wild: 0 },
    ]),
  );
  const photoById = new Map(
    photos.map((p) => [p.id, { ...p, stars: 0, starCount: 0, creative: 0, funny: 0, wild: 0 }]),
  );

  for (const p of photos) {
    const author = stats.get(p.authorId);
    if (author) author.posts++;
  }
  const credit = (photoId, userId, apply) => {
    const photo = photoById.get(photoId);
    if (!photo || userId === photo.authorId) return;
    apply(photo, stats.get(photo.authorId));
    const giver = stats.get(userId);
    if (giver) giver.given++;
  };
  for (const r of reactions) {
    if (!KINDS.includes(r.kind)) continue;
    credit(r.photoId, r.userId, (photo, author) => {
      photo[r.kind]++;
      if (author) author[r.kind]++;
    });
  }
  for (const s of stars) {
    if (!(s.value >= 1 && s.value <= MAX_STARS)) continue;
    credit(s.photoId, s.userId, (photo, author) => {
      photo.stars += s.value;
      photo.starCount++;
      if (author) author.stars += s.value;
    });
  }
  for (const s of stats.values()) {
    s.activity = POINTS.post * Math.min(s.posts, POINTS.postCap) + POINTS.given * s.given;
    s.points = POINTS.star * s.stars + POINTS.reaction * (s.creative + s.funny + s.wild) + s.activity;
  }

  const leaderboard = [...stats.values()].sort(
    (a, b) => b.points - a.points || b.stars - a.stars || a.name.localeCompare(b.name) || a.userId.localeCompare(b.userId),
  );

  // Every photo of the circle with what it collected (authors who left are out).
  const circlePhotos = [...photoById.values()]
    .filter((p) => stats.has(p.authorId))
    .map((p) => ({ ...p, reactions: p.creative + p.funny + p.wild, authorName: stats.get(p.authorId).name }));
  const bestPhoto = bestPhotoOf(circlePhotos);

  // Ordered by points, so ties in a nomination go to whoever has more points overall.
  const leader = (key) => {
    let best = null;
    for (const s of leaderboard) if (s[key] > 0 && (!best || s[key] > best[key])) best = s;
    return best && { userId: best.userId, name: best.name, value: best[key] };
  };

  return {
    leaderboard,
    photos: circlePhotos,
    bestPhoto,
    friendOfWeek: leader('points'),
    mostCreative: leader('creative'),
    mostFunny: leader('funny'),
    mostWild: leader('wild'),
    mostActive: leader('activity'),
  };
}

const earlier = (a, b) => a.createdAt < b.createdAt;

/**
 * Post of the week (or of a day): most stars in total; ties go to more
 * reactions, then the earlier photo. A photo without stars can't win.
 */
export function bestPhotoOf(photos) {
  let best = null;
  for (const p of photos) {
    if (p.stars === 0) continue;
    if (
      !best ||
      p.stars > best.stars ||
      (p.stars === best.stars && (p.reactions > best.reactions || (p.reactions === best.reactions && earlier(p, best))))
    ) {
      best = p;
    }
  }
  return best;
}

/** Most ✍️ / 😂 / 🫪 post: most of that reaction; ties go to more stars, then the earlier photo. */
export function mostReactedPhoto(photos, kind) {
  let best = null;
  for (const p of photos) {
    if (!(p[kind] > 0)) continue;
    if (!best || p[kind] > best[kind] || (p[kind] === best[kind] && (p.stars > best.stars || (p.stars === best.stars && earlier(p, best))))) {
      best = p;
    }
  }
  return best;
}
