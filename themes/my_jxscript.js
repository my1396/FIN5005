function myFunction(id) {
      var x = document.getElementById(id);
      if (!x) return;
      // Read the effective style, not just the inline one: the box starts
      // hidden via the .solution-answer CSS rule, so x.style.display is ""
      // on the first click and a plain inline check would need two clicks.
      var hidden = window.getComputedStyle(x).display === "none";
      x.style.display = hidden ? "block" : "none";
}
