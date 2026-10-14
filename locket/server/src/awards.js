export const KINDS = ['fire', 'creative', 'funny'];

// Points for the weekly leaderboard. "Friend of the week" is whoever has the
// most points; "most active" only looks at the activity part.
export const POINTS = {
  fire: 2, // each 🔥 your photos received
  creative: 1, // each 🎨
  funny: 1, // each 😂
  post: 2, // each photo you posted…
  postCap: 14, // …counted up to this many per week, so spamming doesn't win
  given: 1, // each reaction you gave to friends' photos
};

export function photoScore(p) {
  return POINTS.fire * p.fire + POINTS.creative * p.creative + POINTS.funny * p.funny;
}

/**
 * @param {{ members: {id: string, name: string}[],
 *           photos: {id: string, authorId: string, createdAt: number, caption?: string|null, file: string}[],
 *           reactions: {photoId: string, userId: string, kind: string}[] }} input
 */
export function computeStandings({ members, photos, reactions }) {
  const stats = new Map(
    members.map((m) => [
      m.id,
      { userId: m.id, name: m.name, points: 0, activity: 0, posts: 0, given: 0, fire: 0, creative: 0, funny: 0 },
    ]),
  );
  const photoById = new Map(photos.map((p) => [p.id, { ...p, fire: 0, creative: 0, funny: 0 }]));

  for (const p of photos) {
    const author = stats.get(p.authorId);
    if (author) author.posts++;
  }
  for (const r of reactions) {
    const photo = photoById.get(r.photoId);
    if (!photo || !KINDS.includes(r.kind) || r.userId === photo.authorId) continue;
    photo[r.kind]++;
    const author = stats.get(photo.authorId);
    if (author) author[r.kind]++;
    const giver = stats.get(r.userId);
    if (giver) giver.given++;
  }
  for (const s of stats.values()) {
    s.activity = POINTS.post * Math.min(s.posts, POINTS.postCap) + POINTS.given * s.given;
    s.points = photoScore(s) + s.activity;
  }

  const leaderboard = [...stats.values()].sort(
    (a, b) => b.points - a.points || b.fire - a.fire || a.name.localeCompare(b.name) || a.userId.localeCompare(b.userId),
  );

  let bestPhoto = null;
  for (const p of photoById.values()) {
    if (!stats.has(p.authorId)) continue; // left the circle
    const score = photoScore(p);
    if (score === 0) continue;
    if (
      !bestPhoto ||
      score > bestPhoto.score ||
      (score === bestPhoto.score && (p.fire > bestPhoto.fire || (p.fire === bestPhoto.fire && p.createdAt < bestPhoto.createdAt)))
    ) {
      bestPhoto = { ...p, score, authorName: stats.get(p.authorId).name };
    }
  }

  // The leaderboard is already ordered by points, so ties in a nomination go
  // to whoever has more points overall.
  const leader = (key) => {
    let best = null;
    for (const s of leaderboard) if (s[key] > 0 && (!best || s[key] > best[key])) best = s;
    return best && { userId: best.userId, name: best.name, value: best[key] };
  };

  return {
    leaderboard,
    bestPhoto,
    friendOfWeek: leader('points'),
    mostCreative: leader('creative'),
    mostFunny: leader('funny'),
    mostActive: leader('activity'),
  };
}
