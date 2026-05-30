/**
 * Test script to verify scorecard parsing works
 * Run: node test-scorecard.js
 */

import axios from 'axios';
import { readFileSync } from 'fs';

const MATCH_ID = '155398';

// Test with the downloaded HTML file
console.log('Testing scorecard parser with local HTML file...\n');

try {
  const html = readFileSync('../scorecard-155398.html', 'utf-8');
  console.log(`HTML file size: ${html.length} bytes`);
  
  // Test Next.js JSON extraction
  const nextDataPattern = /self\.__next_f\.push\(\[1,"([^"]+)"\]\)/g;
  let match;
  let jsonChunks = 0;
  
  while ((match = nextDataPattern.exec(html)) !== null) {
    jsonChunks++;
  }
  
  console.log(`Found ${jsonChunks} Next.js JSON chunks`);
  
  // Test traditional HTML patterns
  const inningsPattern = /<div[^>]*id="innings_(\d+)"[^>]*>/gi;
  const inningsMatches = html.match(inningsPattern);
  console.log(`Found ${inningsMatches ? inningsMatches.length : 0} innings divs`);
  
  // Test title extraction
  const titleMatch = html.match(/<title>([^<]*)<\/title>/i);
  if (titleMatch) {
    console.log(`Page title: ${titleMatch[1]}`);
    
    // Look for score patterns
    const scorePattern = /(\w+)\s+(\d+)\/(\d+).*?vs.*?(\w+)\s+(\d+)\/(\d+)/i;
    const scoreMatch = titleMatch[1].match(scorePattern);
    if (scoreMatch) {
      console.log(`\nExtracted scores from title:`);
      console.log(`  ${scoreMatch[1]}: ${scoreMatch[2]}/${scoreMatch[3]}`);
      console.log(`  ${scoreMatch[4]}: ${scoreMatch[5]}/${scoreMatch[6]}`);
    }
  }
  
  console.log('\n✅ HTML file loaded successfully');
  console.log('The parser should be able to extract data from this file.');
  
} catch (err) {
  console.error('❌ Error:', err.message);
}

// Test live API
console.log('\n\nTesting live API endpoint...\n');

axios.get('https://api.webcrichd.co/match/155398/scorecard', {
  headers: { 'Accept': 'application/json' }
})
.then(response => {
  console.log('API Response:');
  console.log(JSON.stringify(response.data, null, 2));
  
  if (response.data.success && response.data.data.innings && response.data.data.innings.length > 0) {
    console.log('\n✅ Scorecard API is working!');
    console.log(`Found ${response.data.data.innings.length} innings`);
  } else {
    console.log('\n❌ Scorecard API returned empty innings');
    console.log('Backend may need to be restarted to load new code');
  }
})
.catch(err => {
  console.error('❌ API Error:', err.message);
});
