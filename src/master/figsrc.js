  // where a figure comes from: a page of the book, or a slide / a frame of a lecture (f.time)
  function figSrc(f, long) {
    if (f.src) return `${f.src}, ${f.time}`;
    if (f.time) return long ? `Слайд лекции, ${f.time}` : `Слайд, ${f.time}`;
    return long ? `${f.n}, страница ${f.p}` : `${f.n}, с. ${f.p}`;
  }
